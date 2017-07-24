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

class WebSocketClient
  def initialize(socket, opts = {})
    @socket = socket
    @logger = opts[:logger]

    # sent to indicate that the connection is closing
    # the only time this should be true is when the server initiates
    # a connection_close_frame and is waiting for the client response
    @closing = false
    @previous_opcode = nil
  end

  def serve
    loop do
      # BASE FRAMING PROTOCOL (from https://tools.ietf.org/html/rfc6455)
      # | ---------------------- 32-bit word -------------------------- |
      # |                                                               |
      # |               |1 1 1 1 1 1    |2 2 2 2 1 1 1 1|3 3 2 2 2 2 2 2|
      # |7 6 5 4 3 2 1 0|5 4 3 2 1 0 9 8|3 2 1 0 9 8 7 6|1 0 9 8 7 6 5 4|
      # +-+-+-+-+-------+-+-------------+-------------------------------+
      # |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
      # |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
      # |N|V|V|V|       |S|             |   (if payload len==126/127)   |
      # | |1|2|3|       |K|             |                               |
      # +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
      # |     Extended payload length continued, if payload len == 127  |
      # + - - - - - - - - - - - - - - - +-------------------------------+
      # |                               |Masking-key, if MASK set to 1  |
      # +-------------------------------+-------------------------------+
      # | Masking-key (continued)       |          Payload Data         |
      # +-------------------------------- - - - - - - - - - - - - - - - +
      # :                     Payload Data continued ...                :
      # + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
      # |                     Payload Data continued ...                |
      # +---------------------------------------------------------------+

      # The first two bytes in any frame always include the header byte
      # and the frame length
      header, len = @socket.recv(2).unpack('C*')
      # a connection may be closed by the client and recv will still return
      return unless header && len
      # FIN is set when this is either a control message or the last frame
      # in a fragmented message
      last_frame = (header & (1 << 7)) > 0
      # NOTE not validated: bits [4-6] of the header should always be unset
      opcode = (header & 0xf)
      is_masked = (len & (1 << 7)) > 0

      # Handle message fragmentation
      # See notes on Fragmentation in the RFC:
      # https://tools.ietf.org/html/rfc6455#section-5.4

      continuation = opcode.zero?
      control_frame = opcode >= 8
      fragment_in_progress = !@previous_opcode.nil?

      # Handle fragmentation error states

      # control frames must not be fragmented
      if control_frame && !last_frame
        @logger.error "Control frame (#{opcode}) cannot be fragmented"
        socket.close
        return

      # fragments must not be interleaved (since we don't support extensions)
      # with non-control frames
      elsif fragment_in_progress && !continuation && !control_frame
        @logger.error "Received invalid opcode (#{opcode}) during fragmented transfer"
        socket.close
        return

      # cannot receive continuation messages unless there's already a
      # fragmented message in progress
      elsif continuation && !fragment_in_progress
        @logger.error 'Received invalid continuation frame'
        socket.close
        return

      end

      unless control_frame
        # Use the previous opcode if there is a fragment in progress
        opcode = @previous_opcode || opcode
        # reset the opcode if this is the last frame
        @previous_opcode = last_frame ? nil : opcode
      end

      # special cases with the payload size:
      # if 126, next 2 bytes are the real size
      # if 127, next 8 bytes are the real size
      payload_size = (len & 0x7f)
      if payload_size == 126
        # unpack as network-order 16-bit unsigned integer
        payload_size = @socket.recv(2).unpack('n').first
      elsif payload_size == 127
        # unpack as two network-order 32-bit unsigned integers
        size_words = @socket.recv(8).unpack('N')
        # append the integers for the full length
        payload_size = size_words[0] << 32 + size_words[1]
      end
      @logger.info "Payload size: #{payload_size} B"

      # If the 'MASK' bit was set, then 4 bytes are provided to the server
      # to be used as an XOR mask for incoming bytes
      # These bytes do *not* count against the payload size
      mask = is_masked ? @socket.recv(4).unpack('C*') : nil

      # Receive the entire payload
      # NOTE that this would need to be done differently to handle large
      # payload transfers since we read the entire payload before moving on,
      # making us vulnerable to clients sending large payloads
      payload = StringIO.new
      payload.set_encoding('BINARY')
      while payload_size > 0
        # read the payload in chunks
        to_read = [1024, payload_size].min
        payload_size -= to_read

        data = @socket.recv(to_read).unpack('C*')
        data = data.each_with_index.map {|b, idx| b ^ mask[idx & 3] } if mask
        payload.write data.pack('C*')
      end

      case opcode
      when 0
        # opcode should be overridden by the original opcode for a fragmented
        # message when a continuation frame is sent
        @logger.error 'Recieved ambiguous contination frame'
        socket.close
        return
      when 1
        text_frame(payload, last_frame)
      when 2
        binary_frame(payload, last_frame)
      # control frames are >= 8 (bit 3 is set)
      when 8
        connection_close_frame(payload)
      when 9
        ping_frame(payload)
      when 10
        pong_frame(payload)
      else
        @logger.error("Unsupported opcode: #{opcode}")
        socket.close
        return
      end
    end
  end

  def text_frame(payload, last_frame)
    @logger.info "Received: #{payload.string.inspect}"
    send_frame(1, 'Hello!')
  end

  def binary_frame(payload, last_frame)
  end

  def connection_close_frame(payload)
  end

  # May include application data; must response with a pong frame unless
  # we are closing the connection
  def ping_frame(payload)
  end

  # Send in response to a ping frame initiated on this end OR as an attempt
  # on the client side to keep the connection alive unilaterally
  def pong_frame(payload)
  end

  # sends a WebSocket frame to the client with the given opcode
  # determines all other field
  def send_frame(opcode, payload = '', last_frame = true)
    payload = payload.force_encoding('BINARY')
    header = (last_frame ? 0x80 : 0) | opcode
    @socket.send(header.chr, 0)

    if payload.length < 126
      @socket.send(payload.length.chr, 0)
    elsif payload.length < (2**16)
      @socket.send(126.chr, 0)
      @socket.send([payload.length].pack('n'), 0)
    else
      @socket.send(127.chr, 0)
      len = [(payload.length >> 32), (payload.length & 0xffffffff)].pack('N')
      @socket.send(len, 0)
    end

    @socket.send(payload, 0)
  end
end

# This is a stand-alone WebSocket implementation that uses only Ruby sockets
# The emphasis on this implementation is on understanding what is happening
# in the underlying requests, with a secondary goal of this being as concise
# as possible and being contained within a single source file.
#
# References used to build this server include:
# "Building a simple websockets server from scratch in Ruby"
# http://blog.honeybadger.io/building-a-simple-websockets-server-from-scratch-in-ruby/
#
# "RFC 6455 - The WebSocket Protocol"
# https://tools.ietf.org/html/rfc6455
#
# WebSocket Ruby Gem - "Universal Ruby library to handle WebSocket protocol"
# https://github.com/imanel/websocket-ruby
class WebSocketServer
  require 'socket'
  require 'logger'

  # Configures the WebSocketServer, but does not start the server
  # @params [Hash] opts - options hash supporting:
  #   host: hostname from which to serve WebSockets
  #   port: port from which to serve WebSockets
  def initialize(opts = {})
    @host = opts[:host]
    @port = opts[:port]
    @logger = opts[:logger]
    @client_handler = opts[:client_handler] || WebSocketClient
    unless @logger
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::WARN
    end
  end

  # Starts the WebSocket server, spawns a new thread for every request
  def run!
    start_server!
    @server_thread = Thread.new do
      loop do
        Thread.start(@server.accept) do |socket|
          begin
            handle_request(socket)
          rescue => e
            @logger.error e.message
            @logger.error e.backtrace
          ensure
            socket.close
          end
        end
      end
    end
  end

  # Stops the main WebSocket server thread
  def stop!
    @server_thread.kill if @server_thread
  end

  private

  # This handles reading the WebSocket request from a client, validating the
  # request, and then serving content if the request appears to be valid
  # TODO: server should respond to bad requests with "400 Bad Request"
  #
  # @param [TCPSocket] socket - the incoming socket from a WebSocket client
  def handle_request(socket)
    request = ''
    http_request = path = host = origin = nil
    # read the raw HTTP request, line by line, until through the headers
    while (line = socket.gets)
      # the HTTP request (verb, path, version) is the first line
      http_request ||= line
      request += line
      # end of the HTTP request
      break if line.strip.empty?
    end

    # get the requested path from the HTTP request
    if http_request =~ /^GET (\S+) HTTP\/1\.1\s*$/
      path = $1
    else
      @logger.warn 'Received unsupported request type'
      return
    end

    # requred headers

    unless request =~ /^Connection: Upgrade\s*$/i
      @logger.warn 'Received request without "Connection: Upgrade" header'
      return
    end

    unless request =~ /^Upgrade: websocket\s*$/i
      @logger.warn 'Received request without "Upgrade: websocket" header'
      return
    end

    unless request =~ /^Sec-WebSocket-Version: 13\s*$/i
      @logger.warn 'Recieved websocket request with invalid version header'
      return
    end

    if request =~ /^Host: (\S+)\s*$/i
      host = $1
    else
      @logger.warn 'Did not receive valid "Host" header'
      return
    end

    if request =~ /^Sec-WebSocket-Key: (\S+)\s*$/i
      websocket_key = $1
    else
      @logger.warn 'Received invalid websocket request (missing key)'
      return
    end

    # Optional header
    # See notes about "Origin Considerations" in the RFC:
    # https://tools.ietf.org/html/rfc6455#section-10.2
    if request =~ /^Origin: (\S+)\s*$/i
      origin = $1
    end

    @logger.info 'Received websocket key, establishing connection'
    response_to_hash = "#{websocket_key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    websocket_accept = Digest::SHA1.base64digest(response_to_hash)
    response = <<-HEADER
      HTTP/1.1 101 Switching Protocols
      Upgrade: websocket
      Connection: Upgrade
      Sec-WebSocket-Accept: #{websocket_accept}

    HEADER
    response = response.split("\n", -1).map {|l| l.strip}
    response = response.join("\r\n")
    socket.write response
    client = @client_handler.new(socket,
      path: path, host: host, origin: origin,
      logger: @logger,
    )
    # serves indefinitely
    client.serve
  end

  # Starts the listening TCPServer. Note that this is abstracted to allow
  # for overriding default behavior, like adding support for accepting
  # connections over SSL/TLS
  def start_server!
    @logger.info "Listening on #{@host}:#{@port}"
    @server = TCPServer.new(@host, @port)
  end
end


# When this script is run directly, two servers are started with default args:
# - an HTTP server for serving static content
# - a WebSockets server for handling WebSocket requests
#
# For usage instructions, run this script with the '-?' flag
if $PROGRAM_NAME == __FILE__
  require 'optparse'
  require 'webrick'
  require 'logger'

  options = {
    host: '127.0.0.1',
    web_port: 8080,
    socket_port: 4568,
  }
  args = ARGV.dup
  opt_parse = OptionParser.new do |opts|
    opts.banner = "Usage: ./#{File.basename(__FILE__)} [options]"
    opts.on('-h', '--host=HOST', String, 'Host serving content') do |host|
      options[:host] = host
    end
    opts.on('-p', '--web-port=PORT', Integer, 'Port serving HTTP') do |port|
      options[:web_port] = port
    end
    opts.on('-s', '--socket-port=PORT', Integer, 'Port serving WebSocket') do |port|
      options[:socket_port] = port
    end
    opts.on_tail('-?', '--help', 'Display help') do
      puts opt_parse
      exit
    end
  end
  begin
    opt_parse.parse!(args)
  rescue OptionParser::InvalidOption => e
    $stderr.puts "Error - #{e.message}"
    $stderr.puts opt_parse
    exit -1
  end

  http_logger = Logger.new(STDOUT)
  http_logger.level = Logger::WARN

  http_opts = {
    :Host => options[:host],
    :Port => options[:web_port],
    :DocumentRoot => './',
    :Logger => Logger.new(STDOUT),
  }
  http_server = WEBrick::HTTPServer.new http_opts

  ws_logger = Logger.new(STDOUT)
  ws_logger.level = Logger::DEBUG
  sock_opts = {
    host: options[:host],
    port: options[:socket_port],
    logger: ws_logger,
  }
  websocket_server = WebSocketServer.new sock_opts

  [:INT, :TERM].each do |sig|
    trap(sig) { http_server.stop; websocket_server.stop! }
  end
  # non-blocking
  websocket_server.run!
  # blocking
  http_server.start
end
