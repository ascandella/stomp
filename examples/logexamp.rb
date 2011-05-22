require 'rubygems'
require 'stomp'
require 'logger'  # for the 'local' logger
#
$:.unshift(File.dirname(__FILE__))
#
require 'slogger'
#
# A STOMP client program which requires a callback logging facility.
#
llog =        Logger::new(STDOUT)
llog.level =  Logger::DEBUG
llog.debug "Starting"
# //////////////////////////////////////////////////////////////////////////////
mylog = Slogger::new  # The STOMP callback logger
# //////////////////////////////////////////////////////////////////////////////
user =      ENV['STOMP_USER'] ? ENV['STOMP_USER'] : 'guest'
password =  ENV['STOMP_PASSWORD'] ? ENV['STOMP_PASSWORD'] : 'guestpw'
host =      ENV['STOMP_HOST'] ? ENV['STOMP_HOST'] : 'localhost'
port =      ENV['STOMP_PORT'] ? ENV['STOMP_PORT'].to_i : 61613
# //////////////////////////////////////////////////////////////////////////////
hash = { :hosts => [ 
          {:login => user, :passcode => password, :host => host, :port => port},
          ],
          :logger => mylog,
          :max_reconnect_attempts => 5,
        }
# //////////////////////////////////////////////////////////////////////////////
conn = Stomp::Connection.new(hash)
conn.disconnect
# //////////////////////////////////////////////////////////////////////////////
llog.debug "Connection processing complete"
# //////////////////////////////////////////////////////////////////////////////
conn = Stomp::Client.new(hash)
conn.close
# //////////////////////////////////////////////////////////////////////////////
llog.debug "Client processing complete"
# //////////////////////////////////////////////////////////////////////////////
llog.debug "Ending"

