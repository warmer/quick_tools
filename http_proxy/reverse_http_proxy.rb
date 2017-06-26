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

require 'socket'
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
      @content_length = 0
      @headers = []
      @transfer_encodings = []
      @is_server = opts[:is_server]
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
      @content = @socket.read(@content_length) if @content_length > 0
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
      puts line
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
      headers.each {|header| puts header; @socket.puts header}
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
      @cache_dir = opts[:cache_dir] || Dir.pwd
      @cache_writeback = opts[:cache_writeback]
    end

    # Starts the proxy and spawns a new thread for every incoming request
    def run!
      start_server!
      loop do
        Thread.start(@proxy_server.accept) do |socket|
          begin
            handle_request(socket)
          rescue => e
            puts e.message
            puts e.backtrace
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
      client = Client.new(socket)
      # This receives all headers and the entire request body, if there is one
      client.read_request!(host: "#{@remote_host}:#{@remote_port}")

      # Process the request read from the client and respond
      send_response(client)
    end

    # Determines how to respond to the request received by the given client
    # Default implementation of this method is to establish a connection with
    # the remote host, forward the entire request, read the entire response,
    # then forward that response back to the client.
    #
    # @param [ReverseHttpProxy::Client] client - client initiating the request
    def send_response(client)
      server = Client.new(TCPSocket.new(@remote_host, @remote_port), is_server: true)

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
      elsif server.transfer_encodings.include? :chunked
        exchange_chunked_transfer(client, server)
      elsif server.code =~ /^3../
        # redirects do not have any content to transfer
      else
        puts "All transfer encodings: #{server.transfer_encodings.inspect}"
        raise 'Do not know how to handle this response!'
      end
    rescue => e
      puts e.message
      puts e.backtrace
    ensure
      server.close! if server
    end

    # Note that
    def exchange_chunked_transfer(client, server)
      loop do
        length, chunk = server.read_chunk
        puts "Chunk length: #{length}"
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
      puts "Listening on #{@listen_host}:#{@listen_port}"
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
