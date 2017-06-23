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

    def send_response(line)
      @socket.puts(line)
    end

    def send_headers(headers)
      headers.each {|header| @socket.puts header}
    end

    def send_content(content)
      @socket.write(content) if content && content.length > 0
    end

    def close!
      @socket.close
    end

    private

    def parse_request(line)
      @request = line
      if @is_server
        @version, @code, @message = line.split(/\s+/, 3)
      else
        @verb, @resource, @version = line.split(/\s+/, 3)
      end
    end

    def parse_header(line)
      @headers << line
      if line.downcase.start_with? 'content-length: '
        @send_bytes = line.gsub(/^\S+\s+(\d+)\s+$/, '\1').to_i
      end
    end

    def read_content
      # read content if content is being sent
      @content = @socket.read(@send_bytes) if @send_bytes > 0
    end
  end

  # Handles management of incoming connections, over-all proxy configuration,
  # and high-level behavior of the proxy
  class Server
    def initialize(opts)
      raise 'Must provide an options hash' unless opts.is_a? Hash

      @listen_port = opts[:listen_port] || 8080
      @listen_host = opts[:listen_host] || '127.0.0.1'
      @remote_host = opts[:remote_host]
      @remote_port = opts[:remote_port] || 80
      @cache_dir = opts[:cache_dir] || Dir.pwd
      @cache_writeback = opts[:cache_writeback]
    end

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

    def start_server!
      puts "Listening on #{@listen_host}:#{@listen_port}"
      @proxy_server = TCPServer.new(@listen_host, @listen_port)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    listen_port: 8080,
    listen_host: '127.0.0.1',
    remote_port: 80,
    cache_writeback: false,
    cache_dir: Dir.pwd,
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
