=begin

Example STOMP call back logger class.

Optional callback methods:

    on_connecting: connection starting
    on_connected: successful connect
    on_connectfail: unsuccessful connect (will usually be retried)
    on_disconnect: successful disconnect

All methods are optional, at the user's requirements.

If a method is not provided, it is not called (of course.)

IMPORTANT NOTE:  call back logging methods *MUST* not raise exceptions, 
otherwise the underlying STOMP connection will fail in mysterious ways.

Callback parameters: are a copy of the @parameters instance variable for
the Stomp::Connection.

=end

require 'logger'	# use the standard Ruby logger .....

class Slogger
  #
  def initialize(init_parms = nil)
    @log = Logger::new(STDOUT)		# User preference
    @log.level = Logger::DEBUG		# User preference
    @log.info("Logger initialization complete.")
  end

  # Log connecting events
  def on_connecting(parms)
    begin
      # parms: A copy of the Connection's @parameters instance variable (a Hash)
      curr_host = parms[:hosts][0]
      @log.debug("Connecting.... " + curr_host[:host] + ":" + curr_host[:port].to_s)
    rescue
      @log.debug("Connecting.... ooops")
    end
  end

  # Log connected events
  def on_connected(parms)
    begin
      # parms: A copy of the Connection's @parameters instance variable (a Hash)
      curr_host = parms[:hosts][0]
      @log.debug("Connected.... " + curr_host[:host] + ":" + curr_host[:port].to_s)
    rescue
      @log.debug("Connected.... ooops")
    end
  end

  # Log connectfail events
  def on_connectfail(parms)
    begin
      # parms: A copy of the Connection's @parameters instance variable (a Hash)
      curr_host = parms[:hosts][0]
      @log.debug("Connect Fail.... " + curr_host[:host] + ":" + curr_host[:port].to_s)
    rescue
      @log.debug("Connectfail.... ooops")
    end
  end

  # Log disconnect events
  def on_disconnect(parms)
    begin
      # parms: A copy of the Connection's @parameters instance variable (a Hash)
      curr_host = parms[:hosts][0]
      @log.debug("Disconnected.... " + curr_host[:host] + ":" + curr_host[:port].to_s)
    rescue
      @log.debug("Disonnect.... ooops")
    end
  end
end # of class

