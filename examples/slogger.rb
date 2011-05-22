=begin

Example STOMP call back logger.

Optional callback methods

    sl_connect: successful connect
    sl_disconnect: successful disconnect

Note:  call back logging methods *must* not raise exceptions, otherwise the
STOMP connection will fail.

=end
require 'logger'
class Slogger
  #
  def initialize(*parms)
    @log = Logger::new(STDOUT)
    @log.level = Logger::DEBUG
    # @log.debug("Logger initialization complete.")
  end

  # Log connect events
  def sl_connect(*parms)
    begin
      @log.debug("Connected.")
    rescue
    end
  end

  # Log disconnect events
  def sl_disconnect(*parms)
    begin
      @log.debug("Disconnected.")
    rescue
    end
  end

end # of class

