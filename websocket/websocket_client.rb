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

# WebSocket::Client is initialized with an established WebSocket connection.
# There are slight differences in behavior depending on who initiated the
# connection, but otherwise, once the connection is established it is
# symetric (either end can send any supported type of message at any time).
#
# Notes:
# - The client supports no extensions (set with Sec-WebSocket-Extensions).
#   Chrome uses this extension: https://tools.ietf.org/html/rfc7692
#   (but this will handle connections to Chrome just fine without extensions)
module WebSocket
  class Client
    require 'logger'
    require 'socket'
    require 'securerandom'

    OPCODES = {
      0 => :continuation,
      1 => :text,
      2 => :binary,
      8 => :close,
      9 => :ping,
      10 => :pong,
    }.freeze

    # Initializer for an established websocket connection
    #
    # @params [TCPSocket] socket
    # @params Options include:
    #   :logger [Logger] to use for logging (defaults to STDOUT)
    #   :client [Boolean] true when acting as the client, not the server
    #   :handlers [Hash] custom event handlers for different message types
    def initialize(socket, opts = {})
      @socket = socket
      @logger = opts[:logger] || Logger.new(STDOUT)
      @is_client = opts[:is_client]
      @handlers = opts[:handlers] || Hash.new {|h, v| h[v] = []}

      # sent to indicate that the connection is closing
      # the only time this should be true is when the server initiates
      # a connection_close_frame and is waiting for the client response
      @closing = false
      @previous_opcode = nil
      @serve_thread = nil

      @default_handlers = Hash.new {|h, v| h[v] = []}
      set_default_handlers
    end

    def set_default_handlers
      @default_handlers[:ping] << lambda {|_c, body| send_frame(:pong, body)}
      @default_handlers[:close] << lambda do |_c, _b|
        send_frame(:close) unless @closing rescue nil
        @serve_thread.kill
        @socket.close
      end
    end

    # Define custom action handlers for incoming frame events
    # Executes the given block when the specified action occurs
    #
    # @param [Symbol] action - the name of the action
    # @param [Proc or lambda] func - a callable object
    # @param [Block] block - code block
    def on(action, func = nil, &block)
      func ||= block
      @handlers[action] << func
    end

    # Called to immediately stop handling requests
    def stop!
      return unless serving?
      @serve_thread.kill
    end

    # Returns true only when the client is actively serving
    def serving?
      @serve_thread && @serve_thread.alive? && @socket && !@socket.closed?
    end

    # Called to start handling incoming WebSocket frames from a client
    #
    # @return [Thread] the thread handling incoming requests
    def serve!
      @serve_thread = Thread.new do
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

          opcode_type = OPCODES[opcode]
          unless opcode_type
            @logger.error "Unknown opcode: #{opcode}"
            @socket.close
            return
          end

          # A client MUST mask all frames that it sends to the server, and the
          # server MUST close the connection upon receiving an unmasked frame
          unless @is_client || is_masked
            @logger.error 'Detected unmasked frame as server: closing connection'
            @socket.close
            return
          end

          # A server MUST NOT mask ANY frames that it sends to the client, and
          # the client MUST close a connection if it detects a masked frame
          if @is_client && is_masked
            @logger.error 'Detected masked frame as client: closing connection'
            @socket.close
            return
          end

          # Handle message fragmentation
          # See notes on Fragmentation in the RFC:
          # https://tools.ietf.org/html/rfc6455#section-5.4

          continuation = opcode.zero?
          control_frame = opcode >= 8
          fragment_in_progress = !@previous_opcode.nil?

          # Detect fragmentation error states

          # control frames must not be fragmented
          if control_frame && !last_frame
            @logger.error "Control frame (#{opcode}) cannot be fragmented"
            @socket.close
            return
          # fragments must not be interleaved (since we don't support extensions)
          # with non-control frames
          elsif fragment_in_progress && !continuation && !control_frame
            @logger.error "Received invalid opcode (#{opcode}) during fragmented transfer"
            @socket.close
            return
          # cannot receive continuation messages unless there's already a
          # fragmented message in progress
          elsif continuation && !fragment_in_progress
            @logger.error 'Received invalid continuation frame'
            @socket.close
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

          emit(opcode_type, payload)
        end
      end
      @serve_thread
    end

    # Invoke any provided custom handlers for the given event type
    #
    # @param [Symbol] type - the event type
    # @param [Array] *args - arguments to provide to the block handler
    def emit(type, *args)
      # a reference to the calling client is added as the first argument
      args.unshift(self)
      @handlers[type].dup.each { |handler| handler.call(*args) }
      @default_handlers[type].dup.each { |handler| handler.call(*args) }
    end

    # sends a WebSocket frame to the client with the given opcode and
    # determines all other field values.
    # @param [Integer|Symbol] opcode - the opcode (or opcode name symbol) to send
    # @param [String] payload
    # @param [Boolean] first_frame - False when this is a continuation message,
    #   so the opcode should be 0
    # @param [Boolean] last_frame - True when the 'FIN' bit should be set,
    #   indicating there are no additional payloads for this message
    def send_frame(opcode, payload = '', first_frame = true, last_frame = true)
      opcode = OPCODES.key(opcode) if opcode.is_a? Symbol
      payload = payload.string if payload.is_a? StringIO
      payload = payload.force_encoding('BINARY')
      # "continuation" frame
      header = opcode
      # continuation messages don't include opcodes
      header = 0 unless first_frame
      # Control frames (>= 8) and the last frame cannot be a continuation
      # set the FIN bit
      header |= 0x80 if (opcode >= 8 || last_frame)

      ws_header = StringIO.new
      ws_header.set_encoding('BINARY')

      ws_header.write(header.chr)
      # the MASK bit must be set for all client frames
      payload_len = @is_client ? 0x80 : 0

      # determine the length to send in the request
      if payload.length < 126
        ws_header.write((payload_len | payload.length).chr)
      elsif payload.length < (2**16)
        ws_header.write((126 | payload_len).chr)
        ws_header.write([payload.length].pack('n'))
      else
        ws_header.write((127 | payload_len).chr)
        len = [(payload.length >> 32), (payload.length & 0xffffffff)].pack('N')
        ws_header.write(len)
      end

      # there must be a random 4-byte mask when sending as the client
      if @is_client
        mask_string = SecureRandom.random_bytes(4)
        ws_header.write(mask_string)

        # XOR each byte in the payload with the mask before sending
        mask = mask_string.unpack('C*')
        masked_data = payload.unpack('C*').each_with_index.map {|b, idx| b ^ mask[idx & 3] }
        payload = masked_data.pack('C*')
      end

      @closing = true if OPCODES[opcode] == :close

      @socket.send(ws_header.string, 0)
      @socket.send(payload, 0)
    end

    # Connect, as a client, to the given host:port and path
    # This will complete negotiation of an outgoing WebSocket connection,
    # including the generation and validation of the WebSocket Key/Accept
    # headers. Note that this does NOT being serving immediate to allow the
    # application to properly set handlers for incoming requests
    #
    # @param [String] host - destination websocket server host
    # @param [String] port - port for the destination websocket server
    # @param [Hash] opts - optional behavior overrides:
    #   :logger - the Ruby Logger object (or compatible) for client logging
    #   :origin - the Origin to specify in the headers when connecting
    #   :headers - any additional non-required headers
    # @return [WebSocket::Client] when connection successfully established
    def self.connect(host, port, opts = {})
      logger = opts[:logger]
      origin = opts[:origin]
      path = opts[:path] || '/'
      headers = opts[:headers] || []
      user_agent = opts[:user_agent] || 'WebSocket::Client'

      # establish the TCPSocket connection
      socket = TCPSocket.new(host, port.to_i)

      # generate the initial request to the TCP socket
      host_header = host
      host_header += ":#{port.to_s}" unless port.to_s == '80'
      # for the server to hash with a constant and send back in the response
      websocket_key = SecureRandom.base64(16)
      request = [
        # base HTTP request
        "GET #{path} HTTP/1.1",

        # required for WebSocket
        "Host: #{host_header}",
        'Connection: Upgrade',
        'Upgrade: websocket',
        # as of the time this was written, the only officially-supported version
        'Sec-WebSocket-Version: 13',
        "Sec-WebSocket-Key: #{websocket_key}",

        # required to successfully use with proxies
        'Pragma: no-cache',
        'Cache-Control: no-cache',

        # some remote servers won't handle requests without user agents
        "User-Agent: #{user_agent}",
      ]
      # Origin is sent by all browsers, but not necessarily for non-browsers
      # If asked, this will send the origin
      request << "Origin: #{origin}" unless origin.nil? || origin.empty?
      # an "empty header" delimits HTTP headers from the body of the request
      request << ''
      request << ''

      begin
        request = request.join("\r\n")
        # send the request
        socket.write request

        response_line = acceptance = connection = upgrade = nil
        # read the response
        while(!(line = socket.readline.strip).empty?)
          if response_line
            case line
            when /^connection: (.*)$/i
              connection = $1
            when /^upgrade: (.*)$/i
              upgrade = $1
            when /^sec-websocket-accept: (.*)$/i
              acceptance = $1
            else
              # don't care
            end
          else
            response_line = line
            proto, code, msg = response_line.split(' ')
            raise "Unsupported protocol: #{proto.inspect}" unless proto == 'HTTP/1.1'
            raise "Invalid response code: #{code.inspect}" unless code == '101'
            raise "Invalid HTTP message: #{msg.inspect}" if msg.nil? || msg.empty?
          end
        end
        raise 'WebSocket Upgrade header not "websocket"' unless upgrade == 'websocket'
        raise 'WebSocket Connection header not "Upgrade"' unless connection == 'Upgrade'
        # validate the acceptance haeder
        response_to_hash = "#{websocket_key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        websocket_accept = Digest::SHA1.base64digest(response_to_hash)
        raise 'Invalid WebSocket acceptance' unless acceptance == websocket_accept
      rescue => e
        logger.error e.message
        logger.info 'Client shutting down'
        socket.close unless socket.closed?
      end

      self.new(socket,
        path: path, host: host, origin: origin, is_client: true,
        logger: logger,
      )
    end
  end
end
