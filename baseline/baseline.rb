#!/usr/bin/env ruby

require 'open3'
require 'optparse'
require 'tempfile'

class Baseline
  def self.run_tests(files, options = {})
    files = files.reject {|f| f.end_with?('.baseline') }
    skipped = skip_unexecutable(files, options)
    files -= skipped
    # skip files without baselines unless we're updating baselines
    skipped += skip_missing_baselines(files, options) unless options[:update]
    results = capture_tests(files - skipped, options)

    results.concat(skipped.map {|f| {file: f, status: :skipped} } )
  end

  private

  def self.capture_tests(files, options = {})
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

  def self.skip_unexecutable(files, options)
    skipped = files.reject {|f| File.executable?(f) }
    skipped.each {|f| log_result(f, 'NOT EXECUTABLE') } unless options[:silent]
    skipped
  end

  def self.skip_missing_baselines(files, options)
    skipped = files.reject {|f| File.exist?("#{f}.baseline") }
    skipped.each {|f| log_result(f, 'MISSING') } unless options[:silent]
    skipped
  end

  def self.log_result(file, result)
    result = "[ #{result} ]"
    name = File.basename(file)
    $stdout.puts "#{name.ljust(79 - result.length, ' ')} #{result}"
    $stdout.flush
  end

  def self.start_test_log(file)
    $stdout.print "#{File.basename(file).ljust(68, ' ')} "
    $stdout.flush
  end

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

  def self.bin_encode(string)
    string.force_encoding('ASCII-8BIT')
  end

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
    summary = 'No tests run' if summary.empty?
    summary.empty? ? 'No tests run' : summary.join('; ')
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

    silent_help = 'Silent: do not print any status during testing'
    opts.on('-s', silent_help) { options[:silent] = true }

    quiet_help = 'Quiet: do not print diff/stderr on failures'
    opts.on('-q', quiet_help) { options[:quiet] = true }

    recursive_help = 'Recursively scan any given directories for tests'
    opts.on('-r', recursive_help) { options[:recursive] = true }

    full_diff_help = 'Adds all baseline context to any diff'
    opts.on('-f', full_diff_help) { options[:full_diff] = true }

    opts.on_tail('-h', '-?', '--help', 'Show help') { puts opts; exit }
  end
  opts.parse!(switches)

  dirs = files.select { |f| File.directory? f }
  files -= dirs
  dirs.collect! do |d|
    pattern = File.join(d, options[:recursive] ? '**/*' : '*')
    Dir.glob(pattern).select { |f| File.file?(f) && File.executable?(f) }
  end
  files += dirs.flatten
  files = files.map { |f| File.expand_path(f) }.sort.uniq

  results = Baseline.run_tests(files, options)
  puts Baseline.summarize(results) unless options[:silent]
  failures = results.select {|result| result[:status] == :failed}.count
  exit([failures, 127].min)
end
