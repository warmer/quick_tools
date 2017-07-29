require 'logger'
require 'digest'
require 'timeout'
require_relative '../server.rb'

class Harness
  PROJ_ROOT ||= File.dirname(File.dirname(File.expand_path(__FILE__)))

  def initialize(opts = {})
    @port = opts[:port] || 9881
    @host = opts[:host] || 'localhost'
    @log = StringIO.new
  end

  def self.run_test(opts = {}, &blk)
    harness = Harness.new(opts)
    harness.instance_exec(&blk)
  end

  def start_websocket_server
    options = {
      port: @port,
      host: @host,
      logger: make_logger,
    }
    @socket_server = WebSocketServer.new(options)
    @socket_server.run!
    Timeout::timeout(1) { @socket_server.running? }
    @socket_server
  end

  def stop_websocket_server
    @socket_server.stop! if @socket_server
  end

  def make_logger
    log = Logger.new(@log)
    log.formatter = proc { |sev, dt, name, msg|
      "#{sev.to_s.ljust(6, ' ')} #{name} #{msg.to_s.strip}\n"
    }
    log.level = Logger::INFO
    log
  end

  def connect(opts = {})
    Timeout::timeout(1) do
      WebSocketClient.connect(@host, @port, opts.merge(logger: make_logger))
    end
  end

  def sanitize(line)
    line.gsub(/:#{@port}/, ':[WEBSOCKET_PORT]')
  end

  def log(line = '')
    puts sanitize(line)
    $stdout.flush
  end

  def scenario(name)
    log '#' * 80
    log "# #{name}#{' ' * (76 - name.length)} #"
    log '#' * 80
    log
  end
end