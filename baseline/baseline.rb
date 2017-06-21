#!/usr/bin/env ruby

# MIT License
#
# Copyright (c) 2017 Kenneth Kinion
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'open3'
require 'optparse'
require 'tempfile'

# Baseline is a tool for running test scripts that have deterministic
# standard output. The test scripts can be written in any language supported
# by the system running the tests. Baseline is designed to work on *nix
# environments, and with modifications, may work on other environments.
#
# Usage:
#  * To create a baseline of a script with deterministic output:
#    > ./baseline -b [script]
#    Creates [script].baseline
#
# * To test a script with an existing baseline:
#   > ./baseline [script]
#   Runs [script], captures its output, and compares against [script].baseline
#
# For all supported options, run ./baseline --help
#
# Note that Baseline supports considerably more functionality than the bare
# minimum required to capture and compare stdout. It was written to support
# most common use cases out-of-the-box with no modification, and could be
# modified quickly, as needed, to support a variety of additional
# uses cases and reporting needs.
class Baseline
  # This runs the given list of tests and returns the results as an array
  # of hashes. By default, with no modifiers, the given test scripts
  #
  # @param [Array] files - list of individual test scripts
  # @param [Hash] options - optional modifiers to the default behavior
  def self.run_tests(files, options = {})
    # find any directories passed in the files list
    dirs = files.select { |f| File.directory? f }
    files -= dirs
    # expand the contents of the directories
    dirs.collect! do |d|
      pattern = File.join(d, options[:recursive] ? '**/*' : '*')
      Dir.glob(pattern).select { |f| File.file?(f) && File.executable?(f) }
    end
    # merge the files from any directories into the files list
    files += dirs.flatten
    files = files.sort.uniq
    files = files.reject {|f| f.end_with?('.baseline') }

    skipped = skip_unexecutable(files, options)
    files -= skipped
    # skip files without baselines unless we're updating baselines
    skipped += skip_missing_baselines(files, options) unless options[:update]
    files -= skipped
    results = capture_tests(files, options)

    results.concat(skipped.map {|f| {file: f, status: :skipped} } )
  end

  private

  # Run the given files, capture the output of those executables, and compare
  # against the given baselines, if they exists.
  # Optionally update the baselines when there is a difference and there
  # otherwise isn't any output on stderr.
  #
  # @params [Array] files - list of individual test scripts
  # @params [Hash] options - modifiers to default behavior
  # @return [Array] - results from each test
  def self.capture_tests(files, options)
    files.map do |file|
      bl_path = "#{file}.baseline"
      baseline = File.exist?(bl_path) ? bin_encode(File.read(bl_path)) : nil
      start_test_log(file) unless options[:silent]
      stdout, stderr, status = Open3.capture3(file)
      result = {file: file, stdout: stdout, stderr: stderr}

      if result[:stderr].empty? && bin_encode(result[:stdout]) == baseline
        result[:status] = :passed
      elsif result[:stderr].empty? && options[:update]
        File.write(bl_path, result[:stdout])
        result[:status] = :updated
      else
        result[:status] = :failed
        result[:diff] = diff(bl_path, result[:stdout], options) if File.exist?(bl_path)
      end

      finish_test_log(result, options) unless options[:silent]
      result
    end
  end

  # Finds the files from the given list that are not executable. Print them
  # to stdout by default.
  #
  # @param [Array] files - list of individual test scripts
  # @param [Hash] options - modifiers to default behavior
  # @return [Array] - list of files that are not executable
  def self.skip_unexecutable(files, options)
    skipped = files.reject {|f| File.executable?(f) }
    skipped.each {|f| log_result(f, 'NOT EXECUTABLE') } unless options[:silent]
    skipped
  end

  # Finds the files from the given list that do not have existing baselines.
  # Print them to stdout by default.
  #
  # @param [Array] files - list of individual test scripts
  # @param [Hash] options - modifiers to default behavior
  # @return [Array] - list of files that are missing baselines
  def self.skip_missing_baselines(files, options)
    skipped = files.reject {|f| File.exist?("#{f}.baseline") }
    skipped.each {|f| log_result(f, 'MISSING') } unless options[:silent]
    skipped
  end

  # Formats and prints the given result for the given file
  #
  # @param [String] file - the test script
  # @param [String] result - the result of the test
  def self.log_result(file, result)
    result = "[ #{result} ]"
    $stdout.puts "#{file.ljust(79 - result.length, ' ')} #{result}"
    $stdout.flush
  end

  # Formats and prints the script that is about to be run
  #
  # @param [String] file - the path to the script
  def self.start_test_log(file)
    $stdout.print "#{file.ljust(68, ' ')} "
    $stdout.flush
  end

  # Formats and prints the result of a test run
  #
  # @param [Hash] result - the result of a test
  # @param [Hash] options - additional formatting instructions
  def self.finish_test_log(result, options)
    $stdout.puts "[ #{result[:status].to_s.upcase} ]".rjust(11, ' ')
    unless options[:quiet]
      unless !result[:diff] || options[:update] || result[:diff].empty?
        $stdout.puts result[:diff]
      end
      unless result[:stderr].empty?
        $stdout.puts '======== STDERR ========'
        $stdout.puts result[:stderr]
      end
    end
    $stdout.flush
  end

  # Returns a copy of the given string that is always encoded as ASCII-8BIT
  def self.bin_encode(string)
    string.force_encoding('ASCII-8BIT')
  end

  # Creates a friendly, human-readable summary string for the given results
  def self.summarize(results)
    summary = []
    passed = results.select {|result| result[:status] == :passed }.count
    failed = results.select {|result| result[:status] == :failed }.count
    updated = results.select {|result| result[:status] == :updated }.count
    skipped = results.select {|result| result[:status] == :skipped }.count
    summary << "Passed: #{passed}" if passed > 0
    summary << "Failed: #{failed}" if failed > 0
    summary << "Updated: #{updated}" if updated > 0
    summary << "Skipped: #{skipped}" if skipped > 0
    summary.empty? ? 'No tests to run' : summary.join('; ')
  end

  # returns a full contextual diff of the given file and the test output (string)
  def self.diff(path, test_string, options)
    diff = nil
    test = Tempfile.new([File.basename(path), '.out'])
    begin
      test_string.encode!('ASCII-8BIT')
      test.write(test_string)
      test.close
      # ensures a full contextual diff - the entire file
      args = [
        "--new-line-format='+%L'",
        "--old-line-format='-%L'",
        "--unchanged-line-format=' %L'"
      ].join(' ')
      diff = `diff #{options[:full_diff] ? args : ''} '#{path}' #{test.path}`
    ensure
      test.close unless test.closed?
      test.unlink
    end
    diff
  end
end

# Parses options off of the command line, then calls Baseline.run_tests when
# this script is run directly
if __FILE__ == $PROGRAM_NAME
  opts = ARGV.dup
  switches = opts.select { |x| x.start_with? '-' }
  files = opts.reject { |x| x.start_with? '-' }
  options = {print_output: true, update: false}

  opts = OptionParser.new do |opts|
    opts.banner = "Usage: ./#{File.basename(__FILE__)} [options] FILE..."
    opts.separator 'Runs the selected files, captures/compares the output'
    opts.separator 'Includes all executable files within given directories'

    opts.on('-b', 'Update/create baselines') { options[:update] = true }

    quiet_help = 'Quiet: do not print diff/stderr on failures'
    opts.on('-q', quiet_help) { options[:quiet] = true }

    silent_help = 'Silent: do not print any status during testing'
    opts.on('-s', silent_help) { options[:silent] = true }

    recursive_help = 'Recursively scan any given directories for tests'
    opts.on('-r', recursive_help) { options[:recursive] = true }

    full_diff_help = 'Adds all baseline context to any diff'
    opts.on('-f', full_diff_help) { options[:full_diff] = true }

    opts.on_tail('-h', '-?', '--help', 'Show help') { puts opts; exit }
  end
  begin
    opts.parse!(switches)
  rescue OptionParser::InvalidOption => e
    puts "Error - #{e.message}"
    puts opts
    exit -1
  end

  results = Baseline.run_tests(files, options)
  puts Baseline.summarize(results) unless options[:silent]
  failures = results.select {|result| result[:status] == :failed}.count
  exit([failures, 127].min)
end
