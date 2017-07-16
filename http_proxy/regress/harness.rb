require 'tempfile'
require 'fileutils'
require 'logger'
require 'webrick'
require 'net/http'

module WEBrick
  class HTTPResponse
    def create_error_page
      @body = '***WEBrick Error Page***'
    end
  end
end

class Harness
  PROJ_ROOT ||= File.dirname(File.dirname(File.expand_path(__FILE__)))

  def initialize(dir, opts = {})
    @dir = dir
    @remote_port = opts[:remote_port] || 9880
    @remote_host = opts[:remote_host] || 'localhost'
    @serve_dir = opts[:serve_dir] || File.join(@dir, 'serve')
    @proxy_port = opts[:proxy_port] || 9881
    @proxy_host = opts[:proxy_host] || 'localhost'
    @cache_dir = opts[:cache_dir] || File.join(@dir, 'cache')
    @use_cache = opts[:use_cache]
    @write_cache = opts[:write_cache]
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
      listen_port: @proxy_port,
      listen_host: @proxy_host,
      cache_dir: @use_cache ? @cache_dir : nil,
      write_cache: @write_cache,
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

  def sanitize(line)
    line
      .gsub(/:#{@remote_port}/, ':[REMOTE_PORT]')
      .gsub(/:#{@proxy_port}/, ':[PROXY_PORT]')
  end

  def log(line = '')
    puts sanitize(line)
  end

  def log_response(response)
    info_line = "=== #{response.uri} #{response.code} #{response.msg} ==="
    info_line = sanitize(info_line).ljust(80, '=')
    log info_line
    log "#{response.body}"
    log '=' * info_line.length
  end

  def scenario(name)
    log '#' * 80
    log "# #{name}#{' ' * (76 - name.length)} #"
    log '#' * 80
    log
  end

  def proxy_get(path, headers = {})
    dest = "#{@proxy_host}:#{@proxy_port}"
    request(Net::HTTP::Get, dest, path, headers)
  end

  def origin_get(path, headers = {})
    dest = "#{@remote_host}:#{@remote_port}"
    request(Net::HTTP::Get, dest, path, headers)
  end

  def request(type, dest, path, headers, body = nil)
    uri = URI.parse("http://#{dest}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    request = type.new(uri)
    headers.keys.each { |k| request[k] = headers[k] }
    request.body = body if body
    http.request(request)
  end

  # Returns a list of files that currently exist in the serve dir
  def serve_files
    Dir.glob(File.join(@serve_dir, '*'))
      .map{|f| f.gsub(/#{@serve_dir}\/?/, '')}
      .sort
  end

  # Returns a list of files that currently exist in the cache dir
  def cache_files
    Dir.glob(File.join(@cache_dir, '*'))
      .map{|f| f.gsub(/#{@cache_dir}\/?/, '')}
      .sort
  end
end
