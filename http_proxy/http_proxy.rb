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

    @listen_port = opts[:listen_port] || 80
    @listen_host = opts[:listen_host] || '127.0.0.1'
    @remote_host = opts[:remote_host]
    @cache_dir = opts[:cache_dir] || Dir.pwd
    @cache_writeback = opts[:cache_writeback]
  end

  def run!
    @proxy_server = TCPServer.new(@listen_host, @listen_port)
    loop do
      Thread.start(@proxy_server.accept) do |client|
        request = nil
        headers = []
        # read lines from the socket
        while line = client.gets
          unless request
            request = line
          else
            headers << line
          end
          # end of the HTTP request
          break if line == ''
        end
        # open a connection to the remote host
        # send the request and the (joined) headers
        # receive the response headers from downstream
        # send them back to the client
        # optionally capture the response body
        # close the client when the remote closes its connection
      end
    end
  end
end
