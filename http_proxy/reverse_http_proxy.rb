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
class ReverseHttpProxy
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
      Thread.start(@proxy_server.accept) do |client|
        action = resource = version = request = nil
        send_bytes = 0
        headers = []
        # read lines from the socket
        while line = client.gets
          puts line
          unless request
            request = line
            action, resource, version = line.split /\s+/
          else
            headers << line
            if line.downcase.start_with? 'content-length: '
              send_bytes = line.gsub(/^\S+\s+(\d+)\s+$/, '\1').to_i
            end
          end
          # end of the HTTP request
          break if line.strip == ''
        end
        # read content if content is being sent
        content = client.read(send_bytes) if send_bytes > 0
        # now make the connection downstream
        response_version = code = response_message = response = nil
        receive_bytes = 0
        response_headers = []
        # open a connection to the remote host
        remote = TCPSocket.new @remote_host, @remote_port
        # send the request and the (joined) headers
        remote.write request
        headers.each {|header| remote.write header}
        remote.write(content) if send_bytes > 0
        # receive the response headers from downstream
        while line = remote.gets
          puts line
          unless response
            response = line
            response_version, code, response_message = line.split(/\s+/, 3)
          else
            response_headers << line
            if line.downcase.start_with? 'content-length: '
              receive_bytes = line.gsub(/^\S+\s+(\d+)\s+$/, '\1').to_i
            end
          end
          break if line.strip == ''
        end
        # read content if content is being returned
        response_content = remote.read(receive_bytes) if receive_bytes > 0
        # send them back to the client
        client.puts response
        response_headers.each {|header| client.puts header}
        client.write(response_content) if receive_bytes > 0
        # close the client when the remote closes its connection
        remote.close
        client.close
      end
    end
  end

  def start_server!
    puts "Listening on #{@listen_host}:#{@listen_port}"
    @proxy_server = TCPServer.new(@listen_host, @listen_port)
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
  proxy = ReverseHttpProxy.new(options)
  proxy.run!
end
