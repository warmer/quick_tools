require 'tempfile'
require 'fileutils'
require 'open3'

class Harness
  PROJ_ROOT ||= File.dirname(File.dirname(File.expand_path(__FILE__)))

  def initialize(dir)
    @dir = dir
  end

  def self.run_test(&blk)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(PROJ_ROOT, 'regress/tests'), dir)
      FileUtils.cp(File.join(PROJ_ROOT, 'baseline'), dir)
      FileUtils.cd(dir) do
        harness = Harness.new(dir)
        harness.instance_exec(&blk)
      end
    end
  end

  def log_cmd(cmd)
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
