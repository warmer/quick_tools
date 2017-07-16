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

require 'time'
require 'socket'
require 'logger'
require 'optparse'

# ReverseHttpProxy provides a lightweight, reverse HTTP proxy. This proxy can
# be configured to have different behavior depending on the path of the
# incoming HTTP request.
#
# ReverseHttpProxy supports:
# - Simple pass-through of requests
# - Serving from cache if available before forwarding a request
# - Cache updating and storage
# - Forwarding requests to different endpoints depending on the pattern match
#
# The individual actions within ReverseHttpProxy have been broken out very
# cleanly to allow the class to be extended for custom behavior.
#
# ReverseHttpProxy can be run directly from the command line with several
# configurations:
# * Reverse proxy with read-only local cache - if a file at the requested
#   path exists within the specified directory (defaults to the current
#   working directory, then that file is served. Otherwise, the request
#   passes through to the configured endpoint.
#   `./reverse_http_proxy.rb -r [host/IP] -c [read-only cache dir]`
module ReverseHttpProxy
  # Handles reading and writing to incoming connections, and parsing and
  # understanding the incoming request
  class Client
    attr_reader :verb, :resource, :version, :code, :message, :request
    attr_reader :headers, :content_length, :content, :transfer_encodings

    # Initializer requires a socket that is already established
    def initialize(socket, opts = {})
      @socket = socket
      @verb = @resource = @version = @code = @message = @request = nil
      @content = ''
      @content_length = nil
      @headers = []
      @transfer_encodings = []
      @is_server = opts[:is_server]
      @logger = opts[:logger]
    end

    # Read from our socket and make sense of the incoming request
    #
    # @param [Hash] opts - overrides of default behavior
    #   :host - if provided, overrides interpreted headers with provided host
    #   :skip_content - if provided, does not read the request body
    def read_request!(opts = {})
      host = opts[:host]
      skip_content = opts[:skip_content]
      # read lines from the socket
      while line = @socket.gets
        unless @request
          parse_request(line)
        else
          parse_header(line, host: host)
        end
        # end of the HTTP request
        break if line.strip == ''
      end
      read_content unless skip_content
    end

    # Reads content from the connection. This currently reads the entire
    # content all at once, blocking until @content_length is received
    #
    # @return [String/nil] - request/response content received
    def read_content
      # read content if content is being sent
      if @content_length && @content_length > 0
        @content = @socket.read(@content_length)
      end
    end

    # Reads one chunk from a chunked transfer
    def read_chunk
      # the first line contains the length of the next chunk
      length = @socket.gets
      chunk = @socket.read(length.to_i(16))
      # append to the local copy of the content
      @content += chunk
      # all content is followed by a newline
      @socket.gets
      # the length (as received, in hex) and the content chunk
      [length, chunk]
    end

    # This sends the HTTP response line, which for an HTTP request,
    # contains the verb, the request path, and the HTTP version like this:
    #   GET /path HTTP/1.0
    # ... and for an HTTP response, contains the HTTP version, the status
    # code, and the message corresponding to the status code like this:
    #   HTTP/1.1 404 NOT FOUND
    # @param [String] line - the fully-formed response line
    def send_response(line)
      @logger.info(self.class) { line }
      @socket.puts(line)
    end

    # This sends all given HTTP headers, which are assumed to be already
    # correctly formed and provided as an array of Strings. Note that the
    # default implementation of this proxy assumes that there is a "blank"
    # header at the end of the array that separates the headers from any
    # body of the request, and for correct operation, that "blank" header
    # must also be provided.
    # NOTE:
    #   - headers are already formed as "[HEADER-KEY]: [HEADER VALUE]"
    #   - headers ends with an empty string
    #
    # @param [Array] headers - array of headers to be sent
    def send_headers(headers)
      headers.each do |header|
        @logger.debug(self.class) { header }
        @socket.puts header
      end
    end

    # This sends any given content, raw
    # NOTE: this will not do anything if content.length == 0
    #
    # @param [String] content - the body of the HTTP request
    def send_content(content)
      @socket.write(content) if content && content.length > 0
    end

    # Closes the connection
    def close!
      @socket.close if @socket
    end

    private

    # Parses the first line of any HTTP request or response, populating
    # the relevant instance variables depending on whether this is configured
    # to interpret as the client or the server
    #
    # @param [String] line - the request line
    def parse_request(line)
      @request = line
      line = line.split(/\s+/, 3)
      if @is_server
        @version, @code, @message = line
      else
        @verb, @resource, @version = line
      end
    end

    # Parses and collects headers. The default implementation of this method
    # looks for the content-length header and parses that value into the
    # @content_length instance variable
    #
    # @param [String] line - raw header string
    # @param [String] host - optional override for Host and Referrer headers
    def parse_header(line, opts = {})
      host = opts[:host]
      if host
        line = line.gsub(/^(Host:\s+).*$/, "\\1#{host}")
        line = line.gsub(/^(Referer:\s+https?:\/\/)[^\/]*(.*)$/, "\\1#{host}\\2")
      end
      @headers << line
      line = line.downcase
      if line.start_with? 'content-length: '
        @content_length = line.gsub(/^\S+\s+(\d+)\s*$/, '\1').to_i
      elsif line.start_with? 'transfer-encoding: '
        encodings = line.gsub(/^\S+\s+(.*)$/, '\1')
        @transfer_encodings = encodings.split(/\s*,\s*/).map {|e| e.strip.to_sym}
      end
    end
  end

  # Handles management of incoming connections, over-all proxy configuration,
  # and high-level behavior of the proxy
  class Server
    attr_reader :listen_port, :listen_host, :remote_port, :remote_host
    # Configures a reverse transparent proxy server, but does not start it
    # An options hash is mandatory; see code for options
    def initialize(opts)
      raise 'Must provide an options hash' unless opts.is_a? Hash

      @listen_port = opts[:listen_port] || 8080
      @listen_host = opts[:listen_host] || '127.0.0.1'
      @remote_host = opts[:remote_host]
      @remote_port = opts[:remote_port] || 80
      @logger = opts[:logger]
      # TODO: not yet supported
      #@cache_writeback = opts[:write_cache]
      @cache_dir = opts[:cache_dir]
      @cache_dir = File.expand_path(@cache_dir, Dir.pwd) if @cache_dir
      unless @logger
        @logger = Logger.new(STDOUT)
        @logger.level = Logger::WARN
      end
    end

    # Starts the proxy and spawns a new thread for every incoming request
    def run!
      start_server!
      loop do
        Thread.start(@proxy_server.accept) do |socket|
          begin
            handle_request(socket)
          rescue => e
            @logger.error(self.class) { e.message }
            @logger.error(self.class) { e.backtrace }
          ensure
            socket.close
          end
        end
      end
    end

    private

    # This handles the entire exchange between client and (if needed server)
    # Note that this is deliberately broken into pieces to allow behavior to
    # be overridden in pieces, as needed, depending on the application
    #
    # @param [TCPSocket] socket - the incoming socket from a proxy client
    def handle_request(socket)
      client = Client.new(socket, logger: @logger)
      # This receives all headers and the entire request body, if there is one
      client.read_request!(host: "#{@remote_host}:#{@remote_port}")

      # Process the request read from the client and respond
      send_response(client)
    end

    # Determines if a request from the given client is a cache hit
    #
    # @param [ReverseHttpProxy::Client] client - client with loaded request
    # @return [String|false] the absolute path of a cache hit, or false
    def cache_hit?(client)
      return false unless @cache_dir
      return false unless Dir.exist?(@cache_dir)
      # sanity check the request
      return false unless client.resource && !client.resource.empty?
      # don't use URL params
      resource = client.resource.split('?', 2)[0]
      # join and expand the path
      expanded_path = File.expand_path(File.join(@cache_dir, resource))
      # don't allow requests to read outside the given cache directory
      # (eg: resource = '../../../../tmp/foo.txt')
      return false unless expanded_path.start_with?(@cache_dir)
      # this covers permissions and the file actually existing on disk
      return false unless File.readable?(expanded_path)
      # return true if this is a regular file (eg: not a directory)
      return expanded_path if File.file?(expanded_path)
    end

    def content_type_for(cache_path)
      extension = File.extname(cache_path).gsub(/^\./, '').downcase
      case extension
      # add your content types here
      when /^(htm|html)$/
        'text/html'
      when /^css$/
        'text/css'
      when /^js$/
        'application/javascript'
      when /^txt$/
        'text/plain'
      when /^(bmp|gif|png)$/
        "image/#{$1}"
      when /^(jpg|jpeg)$/
        'image/jpeg'
      else
        nil
      end
    end

    def headers_for(cache_path)
      # TODO: read cached headers, too?
      headers = [
        "Date: #{Time.now.httpdate}",
        "Server: ReverseHttpProxy",
        "Last-Modified: #{File.mtime(cache_path).httpdate}",
        "Content-Length: #{File.size(cache_path)}",
      ]
      content_type = content_type_for(cache_path)
      headers << "Content-Type: #{content_type}" if content_type
      # add an empty line to signify the end of the headers list
      headers << ''
      headers
    end

    # Determines how to respond to the request received by the given client
    # Default implementation of this method is to establish a connection with
    # the remote host, forward the entire request, read the entire response,
    # then forward that response back to the client.
    #
    # @param [ReverseHttpProxy::Client] client - client initiating the request
    def send_response(client)
      if cache_path = cache_hit?(client)
        client.send_response('HTTP/1.0 200 OK')
        client.send_headers(headers_for(cache_path))
        client.send_content(File.read(cache_path))
        return
      end
      server = Client.new(
        TCPSocket.new(@remote_host, @remote_port),
        logger: @logger,
        is_server: true)

      server.send_response(client.request)
      server.send_headers(client.headers)
      server.send_content(client.content)

      # don't read back the content just yet
      server.read_request! skip_content: true
      # send them back to the requester
      client.send_response(server.request)
      client.send_headers(server.headers)

      if server.content_length > 0
        server.read_content
        client.send_content(server.content)
      elsif server.content_length
        # content length of 0, nothing to read or send back
      elsif server.transfer_encodings.include? :chunked
        exchange_chunked_transfer(client, server)
      elsif server.code =~ /^3../
        # redirects do not have any content to transfer
      else
        @logger.info(self.class) { "All transfer encodings: #{server.transfer_encodings.inspect}" }
        raise 'Do not know how to handle this response!'
      end
    rescue => e
      @logger.error(self.class) { e.message }
      @logger.error(self.class) { e.backtrace }
    ensure
      server.close! if server
    end

    # Note that
    def exchange_chunked_transfer(client, server)
      loop do
        length, chunk = server.read_chunk
        @logger.debug(self.class) { "Chunk length: #{length}" }
        client.send_content length
        client.send_content chunk
        client.send_content "\r\n"
        break if chunk.empty?
      end
      puts
    end

    # Starts the listening TCPServer. Note that this is abstracted to allow
    # for overriding default behavior, like adding support for accepting
    # connections over SSL/TLS
    def start_server!
      @logger.info(self.class) { "Listening on #{@listen_host}:#{@listen_port}" }
      @proxy_server = TCPServer.new(@listen_host, @listen_port)
    end
  end
end

# When this script is run directly, the proxy server is started with any
# given default overrides.
# For usage instructions, run this script with the '-?' flag
if $PROGRAM_NAME == __FILE__
  options = {
    listen_port: 8080,
    listen_host: '127.0.0.1',
    remote_port: 80,
    cache: false,
  }
  args = ARGV.dup
  opt_parse = OptionParser.new do |opts|
    opts.banner = "Usage: ./#{File.basename(__FILE__)} [options]"
    opts.on('-h', '--remote-host=HOST', String, 'Remote Host') do |host|
      options[:remote_host] = host
    end
    opts.on('-p', '--remote-port=PORT', Integer, 'Remote Port') do |port|
      options[:remote_port] = port
    end
    opts.on('--listen-host=HOST', String, 'Listen Host') do |host|
      options[:listen_host] = host
    end
    opts.on('--listen-port=PORT', Integer, 'Proxy Port') do |port|
      options[:listen_port] = port
    end
    # TODO: not yet supported
    #write_cache_help = 'Write remote host responses to cache (use with "-d")'
    #opts.on('-w', '--write-cache', write_cache_help) do
    #  options[:write_cache] = true
    #end
    cache_dir_help = 'Directory to use for local cache of requests'
    opts.on('-d', '--cache-dir=PATH', String, cache_dir_help) do |path|
      options[:cache_dir] = path
    end
    opts.on_tail('-?', '--help', 'Display help') do
      puts opt_parse
      exit
    end
  end
  begin
    opt_parse.parse!(args)
  rescue OptionParser::InvalidOption => e
    puts "Error - #{e.message}"
    puts opt_parse
    exit -1
  end
  unless options[:remote_host]
    puts 'The remote host must be provided'
    puts opt_parse
    exit -1
  end
  proxy = ReverseHttpProxy::Server.new(options)
  proxy.run!
end
