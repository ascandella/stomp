module Stomp

  # Low level connection which maps commands and supports
  # synchronous receives
  class Connection

    alias :obj_send :send
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
      @read_semaphore = Mutex.new
      @socket_semaphore = Mutex.new
      
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
      # Need to look into why the following synchronize does not work.
      #@read_semaphore.synchronize do
      
        s = @socket;
        
        s = nil unless connected?
        
        while s.nil? || !@failure.nil?
          @failure = nil
          begin
            s = open_socket
			      @closed = false
			      
	          headers = @connect_headers.clone
	          headers[:login] = @login
	          headers[:passcode] = @passcode
            _transmit(s, "CONNECT", headers)
            @connect = _receive(s)
            # replay any subscriptions.
            @subscriptions.each { |k,v| _transmit(s, "SUBSCRIBE", v) }
            
            @connection_attempts = 0
          rescue
            @failure = $!;
            s=nil;
            raise unless @reliable
            $stderr.print "connect to #{@host} failed: " + $! +" will retry(##{@connection_attempts}) in #{@reconnect_delay}\n";

            raise "Max number of reconnection attempts reached" if max_reconnect_attempts?

            sleep(@reconnect_delay);
            
            @connection_attempts += 1
            
            if @parameters
              change_host
              increase_reconnect_delay
            end
          end
        end
        @socket = s
        return s;
      #end
    end
    
    def connected?
      begin
        test_socket = TCPSocket.open @host, @port
        test_socket.close
        open?
      rescue
        false
      end
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
	    return TCPSocket.open @host, @port unless @ssl
      
      ssl_socket
	  end
	  
	  def ssl_socket
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
      
	    tcp_socket = TCPSocket.new @host, @port
	    ssl = OpenSSL::SSL::SSLSocket.new(tcp_socket, ctx)
	    ssl.connect
	    ssl
	  end
	  
	  def refine_params(params)
	    params = uncamelized_sym_keys(params)
	    
	    {
	      :initial_reconnect_delay => 0.01,
	      :max_reconnect_delay => 30.0,
	      :use_exponential_back_off => true,
	      :back_off_multiplier => 2,
	      :max_reconnect_attempts => 0,
	      :randomize => false,
	      :connect_headers => {},
	      :backup => false,
	      :timeout => -1
	    }.merge(params)
      
	  end
	  
	  def uncamelized_sym_keys(params)
	    uncamelized = {}
	    params.each_pair do |key, value|
	      key = key.to_s.split(/(?=[A-Z])/).join('_').downcase.to_sym
	      uncamelized[key] = value
	    end
	    
	    uncamelized
	  end
    
    def change_host
      @parameters[:hosts].shuffle! if @parameters[:randomize]
      
      # Set first as master and send it to the end of array
      current_host = @parameters[:hosts].shift
      @parameters[:hosts] << current_host
      
      @ssl = current_host[:ssl]
      @host = current_host[:host]
      @port = current_host[:port] || default_port(@ssl)
      @login = current_host[:login] || ""
      @passcode = current_host[:passcode] || ""
      
    end
    
    def default_port(ssl)
      return 61612 if ssl
      
      61613
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
    # Accepts a transaction header ( :transaction => 'some_transaction_id' )
    def send(destination, message, headers = {})
      headers[:destination] = destination
      transmit("SEND", headers, message)
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
        return receive
      end
    end

    # Receive a frame, block until the frame is received
    def __old_receive
      # The recive my fail so we may need to retry.
      while TRUE
        begin
          s = socket
          return _receive(s)
        rescue
          @failure = $!;
          raise unless @reliable
          $stderr.print "receive failed: " + $!;
        end
      end
    end

    def receive
      super_result = __old_receive()
      if super_result.nil? && @reliable
        $stderr.print "connection.receive returning EOF as nil - resetting connection.\n"
        @socket = nil
        super_result = __old_receive()
      end
      return super_result
    end

    private

      def _receive( s )
        line = ' '
        @read_semaphore.synchronize do
          line = s.gets while line =~ /^\s*$/
          return nil if line.nil?

          message = Message.new do |m|
            m.command = line.chomp
            m.headers = {}
            until (line = s.gets.chomp) == ''
              k = (line.strip[0, line.strip.index(':')]).strip
              v = (line.strip[line.strip.index(':') + 1, line.strip.length]).strip
              m.headers[k] = v
            end

            if (m.headers['content-length'])
              m.body = s.read m.headers['content-length'].to_i
              c = RUBY_VERSION > '1.9' ? s.getc.ord : s.getc
              raise "Invalid content length received" unless c == 0
            else
              m.body = ''
              if RUBY_VERSION > '1.9'
                until (c = s.getc.ord) == 0
                  m.body << c.chr
                end
              else
                until (c = s.getc) == 0
                  m.body << c.chr
                end
              end
            end
            #c = s.getc
            #raise "Invalid frame termination received" unless c == 10
          end # message
          return message

        end
      end

      def transmit(command, headers = {}, body = '')
        # The transmit may fail so we may need to retry.
        while TRUE
          begin
            s = socket
            _transmit(s, command, headers, body)
            return
          rescue
            @failure = $!;
            raise unless @reliable
            $stderr.print "transmit to #{@host} failed: " + $!+"\n";
          end
        end
      end

      def _transmit(s, command, headers = {}, body = '')
        @transmit_semaphore.synchronize do
          s.puts command
          headers.each {|k,v| s.puts "#{k}:#{v}" }
          s.puts "content-length: #{body.length}"
          s.puts "content-type: text/plain; charset=UTF-8"
          s.puts
          s.write body
          s.write "\0"
        end
      end

  end

end

