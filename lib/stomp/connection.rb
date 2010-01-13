require 'socket'
require 'monitor'
require 'timeout'

module Stomp

  # Low level connection which maps commands and supports
  # synchronous receives
  class Connection
    attr_reader :connection_frame
    alias :obj_send :send

    def self.default_port(ssl)
      ssl ? 61612 : 61613
    end
    
    # A new Connection object accepts the following parameters:
    #
    #   login             (String,  default : '')
    #   passcode          (String,  default : '')
    #   host              (String,  default : 'localhost')
    #   port              (Integer, default : 61613)
    #   reliable          (Boolean, default : false)
    #   reconnect_delay   (Integer, default : 5)
    #
    #   e.g. c = Connection.new("username", "password", "localhost", 61613, true)
    #
    # Hash:
    #
    #   hash = {
    #     :hosts => [
    #       {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false},
    #       {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false}
    #     ],
    #     :initial_reconnect_delay => 0.01,
    #     :max_reconnect_delay => 30.0,
    #     :use_exponential_back_off => true,
    #     :back_off_multiplier => 2,
    #     :max_reconnect_attempts => 0,
    #     :randomize => false,
    #     :backup => false,
    #     :timeout => -1
    #   }
    #
    #   e.g. c = Connection.new(hash)
    #
    # TODO
    # Stomp URL :
    #   A Stomp URL must begin with 'stomp://' and can be in one of the following forms:
    #
    #   stomp://host:port
    #   stomp://host.domain.tld:port
    #   stomp://user:pass@host:port
    #   stomp://user:pass@host.domain.tld:port
    #
    def initialize(login = '', passcode = '', host = 'localhost', port = 61613, reliable = false, reconnect_delay = 5, connect_headers = {})
      @received_messages = []

      if login.is_a?(Hash)
        hashed_initialize(login)
      else
        @host = host
        @port = port
        @login = login
        @passcode = passcode
        @reliable = reliable
        @reconnect_delay = reconnect_delay
        @connect_headers = connect_headers
        @ssl = false
        @parameters = nil
      end
      
      @transmit_semaphore = Mutex.new
      @read_semaphore = Monitor.new
      
      @subscriptions = {}
      @failure = nil
      @connection_attempts = 0
      
      socket
    end
    
    def hashed_initialize(params)
      
      @parameters = refine_params(params)
      @reliable = true
      @reconnect_delay = @parameters[:initial_reconnect_delay]
      @connect_headers = @parameters[:connect_headers]
      
      #sets the first host to connect
      change_host
    end
    
    # Syntactic sugar for 'Connection.new' See 'initialize' for usage.
    def Connection.open(login = '', passcode = '', host = 'localhost', port = 61613, reliable = false, reconnect_delay = 5, connect_headers = {})
      Connection.new(login, passcode, host, port, reliable, reconnect_delay, connect_headers)
    end

    def socket
      @read_semaphore.synchronize do
        used_socket = @socket
        used_socket = nil if closed?
        
        while used_socket.nil? || !@failure.nil?
          @failure = nil
          begin
            used_socket = open_socket
            # Open complete
            
            connect(used_socket)
            
            @connection_attempts = 0
          rescue
            @failure = $!
            used_socket = nil
            raise unless @reliable
            $stderr.print "connect to #{@host} failed: #{$!} will retry(##{@connection_attempts}) in #{@reconnect_delay}\n"

            raise "Max number of reconnection attempts reached" if max_reconnect_attempts?

            sleep(@reconnect_delay)
            
            @connection_attempts += 1
            
            if @parameters
              change_host
              increase_reconnect_delay
            end
          end
        end
        @socket = used_socket
      end
    end
  
    def refine_params(params)
      params = params.uncamelize_and_symbolize_keys
      
      default_params = {
        :connect_headers => {},
        # Failover parameters
        :initial_reconnect_delay => 0.01,
        :max_reconnect_delay => 30.0,
        :use_exponential_back_off => true,
        :back_off_multiplier => 2,
        :max_reconnect_attempts => 0,
        :randomize => false,
        :backup => false,
        :timeout => -1
      }
      
      default_params.merge(params)
        
    end
    
    def change_host
      @parameters[:hosts].shuffle! if @parameters[:randomize]
      
      # Set first as master and send it to the end of array
      current_host = @parameters[:hosts].shift
      @parameters[:hosts] << current_host
      
      @ssl = current_host[:ssl]
      @host = current_host[:host]
      @port = current_host[:port] || Connection::default_port(@ssl)
      @login = current_host[:login] || ""
      @passcode = current_host[:passcode] || ""
      
    end
    
    def max_reconnect_attempts?
      !(@parameters.nil? || @parameters[:max_reconnect_attempts].nil?) && @parameters[:max_reconnect_attempts] != 0 && @connection_attempts > @parameters[:max_reconnect_attempts]
    end
    
    def increase_reconnect_delay

      @reconnect_delay *= @parameters[:back_off_multiplier] if @parameters[:use_exponential_back_off] 
      @reconnect_delay = @parameters[:max_reconnect_delay] if @reconnect_delay > @parameters[:max_reconnect_delay]
      
      @reconnect_delay
    end

    # Is this connection open?
    def open?
      !@closed
    end

    # Is this connection closed?
    def closed?
      @closed
    end

    # Begin a transaction, requires a name for the transaction
    def begin(name, headers = {})
      headers[:transaction] = name
      transmit("BEGIN", headers)
    end

    # Acknowledge a message, used when a subscription has specified
    # client acknowledgement ( connection.subscribe "/queue/a", :ack => 'client'g
    #
    # Accepts a transaction header ( :transaction => 'some_transaction_id' )
    def ack(message_id, headers = {})
      headers['message-id'] = message_id
      transmit("ACK", headers)
    end

    # Commit a transaction by name
    def commit(name, headers = {})
      headers[:transaction] = name
      transmit("COMMIT", headers)
    end

    # Abort a transaction by name
    def abort(name, headers = {})
      headers[:transaction] = name
      transmit("ABORT", headers)
    end

    # Subscribe to a destination, must specify a name
    def subscribe(name, headers = {}, subId = nil)
      headers[:destination] = name
      transmit("SUBSCRIBE", headers)

      # Store the sub so that we can replay if we reconnect.
      if @reliable
        subId = name if subId.nil?
        @subscriptions[subId] = headers
      end
    end

    # Unsubscribe from a destination, must specify a name
    def unsubscribe(name, headers = {}, subId = nil)
      headers[:destination] = name
      transmit("UNSUBSCRIBE", headers)
      if @reliable
        subId = name if subId.nil?
        @subscriptions.delete(subId)
      end
    end

    # Send message to destination
    #
    # To disable content length header ( :suppress_content_length => true )
    # Accepts a transaction header ( :transaction => 'some_transaction_id' )
    def send(destination, message, headers = {})
      headers[:destination] = destination
      transmit("SEND", headers, message)
    end
    
    # Send a message back to the source or to the dead letter queue
    #
    # Accepts a dead letter queue option ( :dead_letter_queue => "/queue/DLQ" )
    # Accepts a limit number of redeliveries option ( :max_redeliveries => 6 )
    def unreceive(message, options = {})
      options = { :dead_letter_queue => "/queue/DLQ", :max_redeliveries => 6 }.merge options
      # Lets make sure all keys are symbols
      message.headers = message.headers.symbolize_keys
      
      retry_count = message.headers[:retry_count].to_i || 0
      message.headers[:retry_count] = retry_count + 1
      transaction_id = "transaction-#{message.headers[:'message-id']}-#{retry_count}"
      
      begin
        self.begin transaction_id
        
        if client_ack?(message)
          self.ack(message.headers[:'message-id'], :transaction => transaction_id)
        end
        
        if retry_count <= options[:max_redeliveries]
          self.send(message.headers[:destination], message.body, message.headers.merge(:transaction => transaction_id))
        else
          # Poison ack, sending the message to the DLQ
          self.send(options[:dead_letter_queue], message.body, message.headers.merge(:transaction => transaction_id, :persistent => true))
        end
        self.commit transaction_id
      rescue Exception => exception
        self.abort transaction_id
        raise exception
      end
    end
    
    def client_ack?(message)
      headers = @subscriptions[message.headers[:destination]]
      !headers.nil? && headers[:ack] == "client"
    end

    # Close this connection
    def disconnect(headers = {})
      transmit("DISCONNECT", headers)
      
      close_socket
    end

    # Return a pending message if one is available, otherwise
    # return nil
    def poll
      @read_semaphore.synchronize do
        return nil if @socket.nil? || !@socket.ready?
        receive
      end
    end

    # Receive a frame, block until the frame is received
    def __old_receive
      # The recive my fail so we may need to retry.
      while TRUE
        begin
          used_socket = socket
          return _receive(used_socket)
        rescue
          @failure = $!
          raise unless @reliable
          $stderr.print "receive failed: #{$!}"
        end
      end
    end

    def receive
      super_result = __old_receive
      if super_result.nil? && @reliable
        $stderr.print "connection.receive returning EOF as nil - resetting connection.\n"
        @socket = nil
        super_result = __old_receive
      end
      return super_result
    end

    private

      def _receive( read_socket )
        @read_semaphore.synchronize do
          line = read_socket.gets
          return nil if line.nil?

          # If the reading hangs for more than 5 seconds, abort the parsing process
          Timeout::timeout(5, Stomp::Error::PacketParsingTimeout) do
            # Reads the beginning of the message until it runs into a empty line
            message_header = ''
            begin
              message_header += line
              line = read_socket.gets
            end until line =~ /^\s?\n$/

            # Checks if it includes content_length header
            content_length = message_header.match /content-length\s?:\s?(\d+)\s?\n/
            message_body = ''

            # If it does, reads the specified amount of bytes
            char = ''
            if content_length
              message_body = read_socket.read content_length[1].to_i
              raise Stomp::Error::InvalidMessageLength unless parse_char(read_socket.getc) == "\0"
            # Else reads, the rest of the message until the first \0
            else
              message_body += char while read_socket.ready? && (char = parse_char(read_socket.getc)) != "\0"
            end

            # If the buffer isn't empty, reads the next char and returns it to the buffer
            # unless it's a \n
            if read_socket.ready?
              last_char = read_socket.getc
              read_socket.ungetc(last_char) if parse_char(last_char) != "\n"
            end

            # Adds the excluded \n and \0 and tries to create a new message with it
            Message.new(message_header + "\n" + message_body + "\0")
          end
        end
      end

      def parse_char(char)
        RUBY_VERSION > '1.9' ? char : char.chr
      end

      def transmit(command, headers = {}, body = '')
        # The transmit may fail so we may need to retry.
        while TRUE
          begin
            used_socket = socket
            _transmit(used_socket, command, headers, body)
            return
          rescue
            @failure = $!
            raise unless @reliable
            $stderr.print "transmit to #{@host} failed: #{$!}\n"
          end
        end
      end

      def _transmit(used_socket, command, headers = {}, body = '')
        @transmit_semaphore.synchronize do
          # ActiveMQ interprets every message as a BinaryMessage 
          # if content_length header is included. 
          # Using :suppress_content_length => true will suppress this behaviour
          # and ActiveMQ will interpret the message as a TextMessage.
          # For more information refer to http://juretta.com/log/2009/05/24/activemq-jms-stomp/
          suppress_content_length = headers.delete :suppress_content_length
          headers['content-length'] = "#{body.length}" unless suppress_content_length
          
          used_socket.puts command  
          headers.each {|k,v| used_socket.puts "#{k}:#{v}" }
          used_socket.puts "content-type: text/plain; charset=UTF-8"
          used_socket.puts
          used_socket.write body
          used_socket.write "\0"
        end
      end
      
      def open_tcp_socket
        tcp_socket = TCPSocket.open @host, @port
        def tcp_socket.ready?
          r,w,e = IO.select([self],nil,nil,0)
          ! r.nil?
        end

        tcp_socket
      end

      def open_ssl_socket
        require 'openssl' unless defined?(OpenSSL)
        ctx = OpenSSL::SSL::SSLContext.new

        # For client certificate authentication:
        # key_path = ENV["STOMP_KEY_PATH"] || "~/stomp_keys"
        # ctx.cert = OpenSSL::X509::Certificate.new("#{key_path}/client.cer")
        # ctx.key = OpenSSL::PKey::RSA.new("#{key_path}/client.keystore")

        # For server certificate authentication:
        # truststores = OpenSSL::X509::Store.new
        # truststores.add_file("#{key_path}/client.ts")
        # ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
        # ctx.cert_store = truststores

        ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE  

        ssl = OpenSSL::SSL::SSLSocket.new(open_tcp_socket, ctx)
        def ssl.ready?
          ! @rbuffer.empty? || @io.ready?
        end
        ssl.connect
        ssl
      end
      
      def close_socket
        begin
          @socket.close
        rescue
          #Ignoring if already closed
        end

        @closed = true
      end

      def open_socket
        used_socket = @ssl ? open_ssl_socket : open_tcp_socket
        # try to close the old connection if any
        close_socket
        
        @closed = false
        
        used_socket
      end
      
      def connect(used_socket)
        headers = @connect_headers.clone
        headers[:login] = @login
        headers[:passcode] = @passcode
        _transmit(used_socket, "CONNECT", headers)
        @connection_frame = _receive(used_socket)
        # replay any subscriptions.
        @subscriptions.each { |k,v| _transmit(used_socket, "SUBSCRIBE", v) }
      end

  end

end

