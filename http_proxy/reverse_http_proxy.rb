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
    attr_reader :verb, :resource, :version, :request, :headers
    attr_reader :send_bytes, :content

    # Initializer requires a socket that is already established
    def initialize(socket, opts = {})
      @socket = socket
      @verb = @resource = @version = @code = @message = @request = nil
      @send_bytes = 0
      @headers = []
      @is_server = opts[:is_server]
    end

    # Read from our socket and make sense of the incoming request
    def read_request!
      # read lines from the socket
      while line = @socket.gets
        puts line
        unless @request
          parse_request(line)
        else
          parse_header(line)
        end
        # end of the HTTP request
        break if line.strip == ''
      end
      read_content
    end

    # This sends the HTTP response line, which for an HTTP request,
    # contains the verb, the request path, and the HTTP version like this:
    #   GET /path HTTP/1.0
    # ... and for an HTTP response, contains the HTTP version, the status
    # code, and the message corresponding to the status code like this:
    #   HTTP/1.1 404 NOT FOUND
    # @param [String] line - the fully-formed response line
    def send_response(line)
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
      headers.each {|header| @socket.puts header}
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
      @socket.close
    end

    private

    # Parses the first line of any HTTP request or response, populating
    # the relevant instance variables depending on whether this is configured
    # to interpret as the client or the server
    #
    # @param [String] line - the request line
    def parse_request(line)
      @request = line
      if @is_server
        @version, @code, @message = line.split(/\s+/, 3)
      else
        @verb, @resource, @version = line.split(/\s+/, 3)
      end
    end

    # Parses and collects headers. The default implementation of this method
    # looks for the content-length header and parses that value into the
    # @send_bytes instance variable
    #
    # @param [String] line - raw header string
    def parse_header(line)
      @headers << line
      if line.downcase.start_with? 'content-length: '
        @send_bytes = line.gsub(/^\S+\s+(\d+)\s+$/, '\1').to_i
      end
    end

    # Reads content from the connection. This currently reads the entire
    # content all at once, blocking until @send_bytes is received
    # @return [String/nil] - request/response content received
    def read_content
      # read content if content is being sent
      @content = @socket.read(@send_bytes) if @send_bytes > 0
    end
  end

  # Handles management of incoming connections, over-all proxy configuration,
  # and high-level behavior of the proxy
  class Server
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
            request = Client.new(socket)
            request.read_request!

            response = Client.new(TCPSocket.new(@remote_host, @remote_port))
            response.send_response(request.request)
            response.send_headers(request.headers)
            response.send_content(request.content)

            response.read_request!

            # send them back to the requester
            request.send_response(response.request)
            request.send_headers(response.headers)
            request.send_content(response.content)

            # close the requester when the remote closes its connection
            response.close!
            request.close!
          rescue => e
            puts e.message
            puts e.backtrace
          end
        end
      end
    end

    private

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
