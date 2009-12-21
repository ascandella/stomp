require File.dirname(__FILE__) + '/spec_helper'

describe Stomp::Connection do

  before(:each) do
    @parameters = {
      :hosts => [
        {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false},
        {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false}
      ],
      :initial_reconnect_delay => 0.01,
      :max_reconnect_delay => 30.0,
      :use_exponential_back_off => true,
      :back_off_multiplier => 2,
      :max_reconnect_attempts => 0,
      :randomize => false,
      :backup => false,
      :timeout => -1,
      :connect_headers => {},
      :dead_letter_queue => "queue/DLQ",
      :max_redeliveries => 6,
    }
        
    #POG:
    class Stomp::Connection
      def _receive( s )
      end
      
      def _transmit(s, command, headers = {}, body = '')
      end
    end
    
    # clone() does a shallow copy, we want a deep one so we can garantee the hosts order
    normal_parameters = Marshal::load(Marshal::dump(@parameters))
    
    @tcp_socket = mock(:tcp_socket, :close => nil)
    TCPSocket.stub!(:open).and_return @tcp_socket
    @connection = Stomp::Connection.new(normal_parameters)
  end
  
  describe "(created using a hash)" do
    it "should uncamelize and symbolize the main hash keys" do
      used_hash = {
        "hosts" => [
          {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false},
          {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false}
        ],
        "initialReconnectDelay" => 0.01,
        "maxReconnectDelay" => 30.0,
        "useExponentialBackOff" => true,
        "backOffMultiplier" => 2,
        "maxReconnectAttempts" => 0,
        "randomize" => false,
        "backup" => false,
        "timeout" => -1
      }
      
      @connection = Stomp::Connection.new(used_hash)
      @connection.instance_variable_get(:@parameters).should == @parameters
    end
    
    it "should be reliable" do
      @connection.instance_variable_get(:@reliable).should be_true
    end
    it "should start with first host in array" do
      @connection.instance_variable_get(:@host).should == "localhost"
    end
    
    it "should change host to next one with randomize false" do
      @connection.change_host
      @connection.instance_variable_get(:@host).should == "remotehost"
    end
    
    it "should use default port (61613) if none is given" do
      hash = {:hosts => [{:login => "login2", :passcode => "passcode2", :host => "remotehost", :ssl => false}]}
      @connection = Stomp::Connection.new hash
      @connection.instance_variable_get(:@port).should == 61613
    end
    
    describe "when unacknowledging a message" do
      
      class FakeMessage
        attr_accessor :headers, :body
      end
      
      before :each do
        @message = FakeMessage.new
        @message.body = "message body"
        @message.headers = {"destination" => "/queue/original", "message-id" => "ID"}
        
        @transaction_id = "transaction-#{@message.headers["message-id"]}-0"
        
        @retry_headers = {
          :destination => @message.headers["destination"],
          :'message-id' => @message.headers["message-id"],
          :transaction => @transaction_id,
          :retry_count => 1
        }
      end
      
      it "should use a transaction" do
        @connection.should_receive(:begin).with(@transaction_id).ordered
        @connection.should_receive(:commit).with(@transaction_id).ordered
        @connection.unreceive @message
      end
    
      it "should acknowledge the original message if ack mode is client" do
        @connection.should_receive(:ack)
        @connection.subscribe(@message.headers["destination"], :ack => "client")
        @connection.unreceive @message
      end
      
      it "should not acknowledge the original message if ack mode is not client or it did not subscribe to the queue" do      
        @connection.subscribe(@message.headers["destination"], :ack => "client")
        @connection.should_receive(:ack)
        @connection.unreceive @message
        
        # At this time the message headers are symbolized
        @connection.unsubscribe(@message.headers[:destination])
        @connection.should_not_receive(:ack)
        @connection.unreceive @message
        @connection.subscribe(@message.headers[:destination], :ack => "individual")
        @connection.unreceive @message
      end
      
      it "should send the message back to the queue it came" do
        @connection.subscribe(@message.headers["destination"], :ack => "client")
        @connection.should_receive(:send).with(@message.headers["destination"], @message.body, @retry_headers)
        @connection.unreceive @message
      end
      
      it "should increment the retry_count header" do
        @message.headers["retry_count"] = 4
        @connection.unreceive @message
        @message.headers[:retry_count].should == 5
      end
      
      it "should send the message to the dead letter queue as persistent if max redeliveries have been reached" do
        @message.headers["retry_count"] = @parameters[:max_redeliveries] + 1
        transaction_id = "transaction-#{@message.headers["message-id"]}-#{@message.headers["retry_count"]}"
        @retry_headers[:persistent] = true
        @retry_headers[:transaction] = transaction_id
        @retry_headers[:retry_count] = @message.headers["retry_count"] + 1
        @connection.should_receive(:send).with(@parameters[:dead_letter_queue], @message.body, @retry_headers)
        @connection.unreceive @message
      end
      
      it "should rollback the transaction and raise the exception if happened during transaction" do
        @connection.should_receive(:send).and_raise "Error"
        @connection.should_receive(:abort).with(@transaction_id)
        lambda {@connection.unreceive @message}.should raise_error("Error")
      end
    
    end
    
    describe "when using ssl" do

      # Mocking openssl gem, so we can test without requiring openssl  
      module OpenSSL
        module SSL
          VERIFY_NONE = 0
          
          class SSLSocket
          end
          
          class SSLContext
            attr_accessor :verify_mode
          end
        end
      end
      
      before(:each) do
        ssl_parameters = {:hosts => [{:login => "login2", :passcode => "passcode2", :host => "remotehost", :ssl => true}]}
        @ssl_socket = mock(:ssl_socket)
        
        TCPSocket.should_receive(:new).and_return mock(:tcp_socket)
        OpenSSL::SSL::SSLSocket.should_receive(:new).and_return(@ssl_socket)
        @ssl_socket.should_receive(:connect)
        
        @connection = Stomp::Connection.new ssl_parameters
      end
    
      it "should use ssl socket if ssl use is enabled" do
        @connection.instance_variable_get(:@socket).should == @ssl_socket
      end
    
      it "should use default port for ssl (61612) if none is given" do
        @connection.instance_variable_get(:@port).should == 61612
      end
      
    end

    describe "when called to increase reconnect delay" do
      it "should exponentialy increase when use_exponential_back_off is true" do
        @connection.increase_reconnect_delay.should == 0.02
        @connection.increase_reconnect_delay.should == 0.04
        @connection.increase_reconnect_delay.should == 0.08
      end
      it "should not increase when use_exponential_back_off is false" do
        @parameters[:use_exponential_back_off] = false
        @connection = Stomp::Connection.new(@parameters)
        @connection.increase_reconnect_delay.should == 0.01
        @connection.increase_reconnect_delay.should == 0.01
      end
      it "should not increase when max_reconnect_delay is reached" do
        @parameters[:initial_reconnect_delay] = 8.0
        @connection = Stomp::Connection.new(@parameters)
        @connection.increase_reconnect_delay.should == 16.0
        @connection.increase_reconnect_delay.should == 30.0
      end
      
      it "should change to next host on socket error" do
        #connected?
        TCPSocket.should_receive(:open).and_raise "exception"
        #retries the same host
        TCPSocket.should_receive(:open).and_raise "exception"
        #tries the new host
        TCPSocket.should_receive(:open).and_return mock(:tcp_socket)

        @connection.socket
        @connection.instance_variable_get(:@host).should == "remotehost"
      end
      
      it "should use default options if those where not given" do
        expected_hash = {
          :hosts => [
            {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false},
            # Once connected the host is sent to the end of array
            {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false}
          ],
          :initial_reconnect_delay => 0.01,
          :max_reconnect_delay => 30.0,
          :use_exponential_back_off => true,
          :back_off_multiplier => 2,
          :max_reconnect_attempts => 0,
          :randomize => false,
          :backup => false,
          :timeout => -1,
          :connect_headers => {},
          :dead_letter_queue => "queue/DLQ",
          :max_redeliveries => 6
        }
        
        used_hash =  {
          :hosts => [
            {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false},
            {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false}
          ]
        }
        
        @connection = Stomp::Connection.new(used_hash)
        @connection.instance_variable_get(:@parameters).should == expected_hash
      end
      
      it "should use the given options instead of default ones" do
        used_hash = {
          :hosts => [
            {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false},
            {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false}
          ],
          :initial_reconnect_delay => 5.0,
          :max_reconnect_delay => 100.0,
          :use_exponential_back_off => false,
          :back_off_multiplier => 3,
          :max_reconnect_attempts => 10,
          :randomize => true,
          :backup => false,
          :timeout => -1,
          :connect_headers => {:lerolero => "ronaldo"},
          :dead_letter_queue => "queue/Error",
          :max_redeliveries => 10
        }
        
        @connection = Stomp::Connection.new(used_hash)
        received_hash = @connection.instance_variable_get(:@parameters)
        
        #Using randomize we can't assure the hosts order
        received_hash.delete(:hosts)
        used_hash.delete(:hosts)
        
        received_hash.should == used_hash
      end
      
    end
    
  end
  
  describe "when checking if connected" do
    it "should return true if no exceptions are raised" do
      @connection.connected?.should be_true
    end
    it "should return false if any exceptions are raised" do
      TCPSocket.should_receive(:open).and_raise "exception"
      @connection.connected?.should be_false
    end
  end
  
  describe "when closing a socket" do
    it "should close the tcp connection" do
      @tcp_socket.should_receive(:close)
      @connection.close_socket.should be_true
    end
    it "should ignore exceptions" do
      @tcp_socket.should_receive(:close).and_raise "exception"
      @connection.close_socket.should be_true
    end
  end
  
  describe "when checking if max reconnect attempts have been reached" do
    it "should return false if not using failover" do
      host = @parameters[:hosts][0]
      @connection = Stomp::Connection.new(host[:login], host[:passcode], host[:host], host[:port], reliable = true, 5, connect_headers = {})
      @connection.instance_variable_set(:@connection_attempts, 10000)
      @connection.max_reconnect_attempts?.should be_false
    end
    it "should return false if max_reconnect_attempts = 0" do
      @connection.instance_variable_set(:@connection_attempts, 10000)
      @connection.max_reconnect_attempts?.should be_false
    end
    it "should return true if connection attempts > max_reconnect_attempts" do
      limit = 10000
      @parameters[:max_reconnect_attempts] = limit
      @connection = Stomp::Connection.new(@parameters)
      
      @connection.instance_variable_set(:@connection_attempts, limit)
      @connection.max_reconnect_attempts?.should be_false
      
      @connection.instance_variable_set(:@connection_attempts, limit+1)
      @connection.max_reconnect_attempts?.should be_true
    end
  end
end

