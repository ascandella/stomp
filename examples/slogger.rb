=begin

Example STOMP call back logger.

Optional callback methods

    sl_connecting: connection starting
    sl_connected: successful connect
    sl_connectfail: unsuccessful connect (will usually be retried)
    sl_disconnect: successful disconnect

Note:  call back logging methods *must* not raise exceptions, otherwise the
STOMP connection will fail.

=end
require 'logger'
class Slogger
  #
  def initialize(init_parms = nil)
    @log = Logger::new(STDOUT)
    @log.level = Logger::DEBUG
    # @log.debug("Logger initialization complete.")
  end

  # Log connecting events
  def sl_connecting(parms)
    begin
      # parms: A copy of the Connection's @parameters instance variable (a Hash)
      curr_host = parms[:hosts][0]
      @log.debug("Connecting.... " + curr_host[:host] + ":" + curr_host[:port].to_s)
    rescue
    end
  end

  # Log connected events
  def sl_connected(parms)
    begin
      # parms: A copy of the Connection's @parameters instance variable (a Hash)
      curr_host = parms[:hosts][0]
      @log.debug("Connected.... " + curr_host[:host] + ":" + curr_host[:port].to_s)
    rescue
    end
  end

  # Log connectfail events
  def sl_connectfail(parms)
    begin
      # parms: A copy of the Connection's @parameters instance variable (a Hash)
      curr_host = parms[:hosts][0]
      @log.debug("Connect Fail.... " + curr_host[:host] + ":" + curr_host[:port].to_s)
    rescue
    end
  end

  # Log disconnect events
  def sl_disconnect(parms)
    begin
      # parms: A copy of the Connection's @parameters instance variable (a Hash)
      curr_host = parms[:hosts][0]
      @log.debug("Disconnected.... " + curr_host[:host] + ":" + curr_host[:port].to_s)
    rescue
    end
  end

end # of class

