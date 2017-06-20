require 'tempfile'
require 'fileutils'
require 'open3'

class Harness
  BASELINE_NAME ||= 'baseline.rb'
  PROJ_ROOT ||= File.dirname(File.dirname(File.expand_path(__FILE__)))
  BASELINE_SCRIPT ||= File.join(PROJ_ROOT, BASELINE_NAME)
  SOURCE_TEST_DIR ||= File.join(PROJ_ROOT, 'regress/tests')

  def initialize(dir)
    @dir = dir
  end

  def self.run_test(&blk)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(SOURCE_TEST_DIR, dir)
      FileUtils.cp(BASELINE_SCRIPT, dir)
      FileUtils.cd(dir) do
        harness = Harness.new(dir)
        harness.instance_exec(&blk)
      end
    end
  end

  def log_cmd(cmd)
    cmd = "./#{BASELINE_NAME} #{cmd}"
    puts cmd
    stdout_str, status = Open3.capture2(cmd)
    puts stdout_str.gsub(@dir, '[base]')
    puts "Status code: #{status.exitstatus}"
    puts
  end

  def scenario(name)
    puts '#' * 80
    puts "# #{name}#{' ' * (76 - name.length)} #"
    puts '#' * 80
    puts
  end
end
