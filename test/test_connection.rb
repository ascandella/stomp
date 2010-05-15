$:.unshift(File.dirname(__FILE__))

require 'test_helper'

class TestStomp < Test::Unit::TestCase
  include TestBase
  
  def setup
    @conn = Stomp::Connection.open(user, passcode, host, port)
  end

  def teardown
    @conn.disconnect if @conn # allow tests to disconnect
  end

  def test_connection_exists
    assert_not_nil @conn
  end

  def test_explicit_receive
    @conn.subscribe make_destination
    @conn.publish make_destination, "test_stomp#test_explicit_receive"
    msg = @conn.receive
    assert_equal "test_stomp#test_explicit_receive", msg.body
  end

  def test_receipt
    @conn.subscribe make_destination, :receipt => "abc"
    msg = @conn.receive
    assert_equal "abc", msg.headers['receipt-id']
  end

  def test_disconnect_receipt
    @conn.disconnect :receipt => "abc123"
    assert_nothing_raised {
      assert_not_nil(@conn.disconnect_receipt, "should have a receipt")
      assert_equal(@conn.disconnect_receipt.headers['receipt-id'],
        "abc123", "receipt sent and received should match")
    }
    @conn = nil
  end

  def test_client_ack_with_symbol
    @conn.subscribe make_destination, :ack => :client
    @conn.publish make_destination, "test_stomp#test_client_ack_with_symbol"
    msg = @conn.receive
    @conn.ack msg.headers['message-id']
  end

  def test_embedded_null
    @conn.subscribe make_destination
    @conn.publish make_destination, "a\0"
    msg = @conn.receive
    assert_equal "a\0" , msg.body
  end

  def test_connection_open?
    assert_equal true , @conn.open?
    @conn.disconnect
    assert_equal false, @conn.open?
  end

  def test_connection_closed?
    assert_equal false, @conn.closed?
    @conn.disconnect
    assert_equal true, @conn.closed?
  end

  def test_response_is_instance_of_message_class
    @conn.subscribe make_destination
    @conn.publish make_destination, "a\0"
    msg = @conn.receive
    assert_instance_of Stomp::Message , msg
  end

  def test_message_to_s
    @conn.subscribe make_destination
    @conn.publish make_destination, "a\0"
    msg = @conn.receive
    assert_match /^<Stomp::Message headers=/ , msg.to_s
  end
  
  def test_connection_frame
  	assert_not_nil @conn.connection_frame
  end
  
  def test_messages_with_multipleLine_ends
    @conn.subscribe make_destination
    @conn.publish make_destination, "a\n\n"
    @conn.publish make_destination, "b\n\na\n\n"
    
    msg_a = @conn.receive
    msg_b = @conn.receive

    assert_equal "a\n\n", msg_a.body
    assert_equal "b\n\na\n\n", msg_b.body
  end

  def test_publish_two_messages
    @conn.subscribe make_destination
    @conn.publish make_destination, "a\0"
    @conn.publish make_destination, "b\0"
    msg_a = @conn.receive
    msg_b = @conn.receive

    assert_equal "a\0", msg_a.body
    assert_equal "b\0", msg_b.body
  end

  def test_thread_hang_one
    received = nil
    Thread.new(@conn) do |amq|
        while true
            received = amq.receive
        end
    end
    #
    @conn.subscribe( make_destination )
    message = Time.now.to_s
    @conn.publish(make_destination, message)
    sleep 1
    assert_not_nil received
    assert_equal message, received.body
  end

  def test_thread_poll_one
    received = nil
    Thread.new(@conn) do |amq|
        while true
          received = amq.poll
          # One message is needed
          Thread.exit if received
          sleep 0.1
        end
    end
    #
    @conn.subscribe( make_destination )
    message = Time.now.to_s
    @conn.publish(make_destination, message)
    sleep 1
    assert_not_nil received
    assert_equal message, received.body
  end

  def test_multi_thread_receive
    # An arbitrary number
    max_threads = 20
    lock = Mutex.new
    msg_ctr = 0
    #
    1.upto(max_threads) do |tnum|
      Thread.new(@conn) do |amq|
        while true
          received = amq.receive
          lock.synchronize do
            msg_ctr += 1
          end
          # Simulate message processing
          sleep 0.05
        end
      end
    end
    #
    @conn.subscribe( make_destination )
    # Another arbitrary number
    max_msgs = 100
    1.upto(max_msgs) do |mnum|
      msg = Time.now.to_s + " #{mnum}"
      @conn.publish(make_destination, msg)
    end
    # This sleep needs to be 'long enough'
    sleep 1
    # The only assertion in this test method
    assert_equal msg_ctr, max_msgs
  end

  def test_multi_thread_poll
    # An arbitrary number
    max_threads = 20
    lock = Mutex.new
    msg_ctr = 0
    #
    1.upto(max_threads) do |tnum|
      Thread.new(@conn) do |amq|
        while true
          received = amq.poll
          if received
            lock.synchronize do
              msg_ctr += 1
            end
          else
            sleep 0.1
          end
        end
      end
    end
    #
    @conn.subscribe( make_destination )
    # Another arbitrary number
    max_msgs = 100
    1.upto(max_msgs) do |mnum|
      msg = Time.now.to_s + " #{mnum}"
      @conn.publish(make_destination, msg)
    end
    # This sleep needs to be 'long enough'
    sleep 1
    # The only assertion in this test method
    assert_equal msg_ctr, max_msgs
  end

  private
    def make_destination
      "/queue/test/ruby/stomp/" + name
    end

    def _test_transaction
      @conn.subscribe make_destination

      # Drain the destination.
      sleep 0.01 while
      sleep 0.01 while @conn.poll!=nil

      @conn.begin "tx1"
      @conn.publish make_destination, "txn message", 'transaction' => "tx1"

      @conn.publish make_destination, "first message"

      sleep 0.01
      msg = @conn.receive
      assert_equal "first message", msg.body

      @conn.commit "tx1"
      msg = @conn.receive
      assert_equal "txn message", msg.body
    end
end

