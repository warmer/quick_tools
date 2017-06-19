#!/usr/bin/env ruby

require 'tempfile'
require 'fileutils'

baseline_name = 'baseline.rb'
parent_dir = File.dirname(File.expand_path(__FILE__))
baseline_script = File.join(File.dirname(parent_dir), baseline_name)
test_dir = 'tests'
src_dir = File.join(parent_dir, test_dir)

def log_cmd(cmd, dir)
  puts cmd
  puts `#{cmd}`.gsub(dir, '[base]')
end

def scenario(name)
  puts '#' * (name.length + 4)
  puts "# #{name} #"
  puts '#' * (name.length + 4)
  puts
end

Dir.mktmpdir do |dir|
  FileUtils.cp_r(src_dir, dir)
  FileUtils.cp(baseline_script, dir)

  FileUtils.cd(dir) do
    scenario 'Run with a list of files'
    log_cmd "./#{baseline_name} #{test_dir}/*", dir

    scenario 'Run with a directory'
    log_cmd "./#{baseline_name} #{test_dir}", dir

    scenario 'Run with a full diff'
    log_cmd "./#{baseline_name} -f #{test_dir}", dir

    scenario 'Run quietly'
    log_cmd "./#{baseline_name} -q #{test_dir}", dir

    scenario 'Run silently'
    log_cmd "./#{baseline_name} -s #{test_dir}", dir

    scenario 'Update a directory'
    log_cmd "./#{baseline_name} -b #{test_dir}", dir
  end
end
