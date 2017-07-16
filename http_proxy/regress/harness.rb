require 'tempfile'
require 'fileutils'
require 'logger'
require 'webrick'
require 'net/http'

class Harness
  PROJ_ROOT ||= File.dirname(File.dirname(File.expand_path(__FILE__)))

  def initialize(dir, opts = {})
    @dir = dir
    @remote_port = opts[:remote_port] || 9880
    @remote_host = opts[:remote_host] || 'localhost'
    @serve_dir = opts[:serve_dir] || File.join(@dir, 'serve')
    @listen_port = opts[:listen_port] || 9881
    @listen_host = opts[:listen_host] || 'localhost'
    @cache_dir = opts[:cache_dir] || File.join(@dir, 'cache')
    @cache = false
    @remote_log = StringIO.new
    @proxy_log = StringIO.new
  end

  def self.run_test(opts = {}, &blk)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(PROJ_ROOT, 'regress/serve'), dir)
      FileUtils.cp_r(File.join(PROJ_ROOT, 'regress/cache'), dir)
      FileUtils.cp(File.join(PROJ_ROOT, 'reverse_http_proxy.rb'), dir)
      FileUtils.cd(dir) do
        require_relative File.join(dir, 'reverse_http_proxy.rb')
        harness = Harness.new(dir, opts)
        harness.start_proxy
        harness.start_server
        sleep 0.1
        harness.instance_exec(&blk)
        harness.stop_proxy
        harness.stop_server
      end
    end
  end

  def start_server
    opts = {
      :BindAddress => @remote_host,
      :Port => @remote_port,
      :DocumentRoot => @serve_dir,
      :Logger => Logger.new(StringIO.new),
      :AccessLog => [[@remote_log, '%m %U %s %b %{Host}i']]
    }
    @http = WEBrick::HTTPServer.new opts
    @http_thread = Thread.new { @http.start }
  end

  def start_proxy
    proxy_logger = Logger.new(@proxy_log)
    proxy_logger.formatter = proc { |sev, dt, name, msg|
      "#{sev.to_s.ljust(6, ' ')} #{name} #{msg.to_s.strip}\n"
    }
    proxy_logger.level = Logger::INFO
    options = {
      remote_port: @remote_port,
      remote_host: @remote_host,
      listen_port: @listen_port,
      listen_host: @listen_host,
      cache_dir: @cache_dir,
      cache: @cache,
      logger: proxy_logger,
    }
    @proxy = ReverseHttpProxy::Server.new(options)
    @proxy_thread = Thread.new { @proxy.run! }
  end

  def stop_server
    @http_thread.kill if @http_thread
  end

  def stop_proxy
    @proxy_thread.kill if @proxy_thread
  end

  def log_response(response)
    info_line = "=== #{response.uri} #{response.code} #{response.msg} ==="
    puts info_line
    puts "#{response.body}"
    puts '=' * info_line.length
  end

  def scenario(name)
    puts '#' * 80
    puts "# #{name}#{' ' * (76 - name.length)} #"
    puts '#' * 80
    puts
  end

  def proxy_get(path, headers = {})
    dest = "#{@listen_host}:#{@listen_port}"
    request(Net::HTTP::Get, dest, path, headers)
  end

  def origin_get(path, headers = {})
    dest = "#{@remote_host}:#{@remote_port}"
    request(Net::HTTP::Get, dest, path, headers)
  end

  def request(type, dest, path, headers, body = nil)
    uri = URI.parse("http://#{dest}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    puts "Getting from URI: #{uri}"
    request = type.new(uri)
    headers.keys.each { |k| request[k] = headers[k] }
    request.body = body if body
    http.request(request)
  end
end
