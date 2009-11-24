require File.dirname(__FILE__) + '/spec_helper'

describe Stomp::Connection do

  before(:each) do
    @failover = {
      :hosts => [
        {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false},
        {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false}
      ],
      :initialReconnectDelay => 0.01,
      :maxReconnectDelay => 30.0,
      :useExponentialBackOff => true,
      :backOffMultiplier => 2,
      :maxReconnectAttempts => 0,
      :randomize => false,
      :backup => false,
      :timeout => -1
    }
    
    #POG:
    class Stomp::Connection
      def _receive( s )
      end
      
      def _transmit(s, command, headers = {}, body = '')
      end
    end
    
    tcp = mock("tcp_socket")
    TCPSocket.stub!(:open).and_return tcp
    
  end

  describe "(created with open_with_failover method/or using a hash)" do
    it "should be reliable" do
      connection = Stomp::Connection.open_with_failover(@failover)
      connection.instance_variable_get(:@reliable).should be_true
    end
    it "should start with first host in array" do
      connection = Stomp::Connection.open_with_failover(@failover)
      connection.instance_variable_get(:@host).should == "localhost"
    end
    
    it "should change master to next host with randomize false" do
      connection = Stomp::Connection.open_with_failover(@failover)
      connection.change_master
      connection.instance_variable_get(:@host).should == "remotehost"
    end
    
    it "should use default port (61613) if none is given" do
      hash = {:hosts => [{:login => "login2", :passcode => "passcode2", :host => "remotehost", :ssl => false}]}
      connection = Stomp::Connection.new hash
      connection.instance_variable_get(:@port).should == 61613
    end
    
    describe "when using ssl" do

      # Mocking openssl gem    
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
        @hash = {:hosts => [{:login => "login2", :passcode => "passcode2", :host => "remotehost", :ssl => true}]}
        tcp_socket = mock("tcp_socket")
        @ssl_socket = mock("ssl_socket")
        
        TCPSocket.should_receive(:new).and_return(tcp_socket)
        OpenSSL::SSL::SSLSocket.should_receive(:new).and_return(@ssl_socket)
        @ssl_socket.should_receive(:connect)
      end
    
      it "should use ssl socket if ssl use is enabled" do
        
        connection = Stomp::Connection.new @hash
        connection.instance_variable_get(:@socket).should == @ssl_socket
        
      end
    
      it "should use default port for ssl (61612) if none is given" do
        
        connection = Stomp::Connection.new @hash
        connection.instance_variable_get(:@port).should == 61612
        
      end
      
    end

    describe "when called to increase reconnect delay" do
      it "should exponentialy increase when useExponentialBackOff is true" do
        connection = Stomp::Connection.open_with_failover(@failover)
        connection.increase_reconnect_delay.should == 0.02
        connection.increase_reconnect_delay.should == 0.04
        connection.increase_reconnect_delay.should == 0.08
      end
      it "should not increase when useExponentialBackOff is false" do
        @failover[:useExponentialBackOff] = false
        connection = Stomp::Connection.open_with_failover(@failover)
        connection.increase_reconnect_delay.should == 0.01
        connection.increase_reconnect_delay.should == 0.01
      end
      it "should not increase when maxReconnectDelay is reached" do
        @failover[:initialReconnectDelay] = 8.0
        connection = Stomp::Connection.open_with_failover(@failover)
        connection.increase_reconnect_delay.should == 16.0
        connection.increase_reconnect_delay.should == 30.0
      end
      
      it "should change to next host on socket error" do
        connection = Stomp::Connection.open_with_failover(@failover)
        
        #connected?
        TCPSocket.should_receive(:open).and_raise "exception"
        #retries the same host
        TCPSocket.should_receive(:open).and_raise "exception"

        #tries the new host
        TCPSocket.should_receive(:open).and_return mock("tcp_socket")

        connection.socket
        connection.instance_variable_get(:@host).should == "remotehost"
      end
      
      it "should use default options if those where not given" do
        expected_hash = {
          :hosts => [
            {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false},
            # Once connected the host is sent to the end of array
            {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false}
          ],
          :initialReconnectDelay => 0.01,
          :maxReconnectDelay => 30.0,
          :useExponentialBackOff => true,
          :backOffMultiplier => 2,
          :maxReconnectAttempts => 0,
          :randomize => false,
          :backup => false,
          :timeout => -1,
          :connect_headers => {}
        }
        
        used_hash =  {
          :hosts => [
            {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false},
            {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false}
          ]
        }
        
        connection = Stomp::Connection.new(used_hash)
        
        connection.instance_variable_get(:@failover).should == expected_hash
      end
      
      it "should use the given options instead of default ones" do
        used_hash = {
          :hosts => [
            {:login => "login2", :passcode => "passcode2", :host => "remotehost", :port => 61617, :ssl => false},
            # Once connected the host is sent to the end of array
            {:login => "login1", :passcode => "passcode1", :host => "localhost", :port => 61616, :ssl => false}
          ],
          :initialReconnectDelay => 5.0,
          :maxReconnectDelay => 100.0,
          :useExponentialBackOff => false,
          :backOffMultiplier => 3,
          :maxReconnectAttempts => 10,
          :randomize => true,
          :backup => false,
          :timeout => -1,
          :connect_headers => {:lerolero => "ronaldo"}
        }
        
        connection = Stomp::Connection.new(used_hash)
        
        received_hash = connection.instance_variable_get(:@failover)
        
        #Using randomize we can't assure the hosts order
        received_hash.delete(:hosts)
        used_hash.delete(:hosts)
        
        received_hash.should == used_hash
      end
      
    end
    
  end
  
  describe "when checking if connected" do
    it "should return true if no exceptions are raised" do
      connection = Stomp::Connection.open_with_failover(@failover)
      
      connection.connected?.should be_true
    end
    it "should return false if any exceptions are raised" do
      connection = Stomp::Connection.open_with_failover(@failover)
      
      TCPSocket.should_receive(:open).and_raise "exception"
      
      connection.connected?.should be_false
    end
  end
  
  describe "when checking if max reconnect attempts have been reached" do
    it "should return false if not using failover" do
      host = @failover[:hosts][0]
      connection = Stomp::Connection.new(host[:login], host[:passcode], host[:host], host[:port], reliable = true, 5, connect_headers = {})
      
      connection.max_reconnect_attempts?.should be_false
    end
    it "should return false if maxReconnectAttempts = 0" do
      connection = Stomp::Connection.open_with_failover(@failover)
      
      connection.instance_variable_set(:@connection_attempts, 10000)
      connection.max_reconnect_attempts?.should be_false
    end
    it "should return true if connection attempts > maxReconnectAttempts" do
      limit = 10000
      @failover[:maxReconnectAttempts] = limit
      connection = Stomp::Connection.open_with_failover(@failover)
      
      connection.instance_variable_set(:@connection_attempts, limit)
      connection.max_reconnect_attempts?.should be_false
      
      connection.instance_variable_set(:@connection_attempts, limit+1)
      connection.max_reconnect_attempts?.should be_true
    end
  end
end

