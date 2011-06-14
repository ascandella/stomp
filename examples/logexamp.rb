require 'rubygems'
require 'stomp'
require 'logger'  # for the 'local' logger
#
$:.unshift(File.dirname(__FILE__))
#
require 'slogger'
#
# A STOMP client program which uses the callback logging facility.
#
llog =        Logger::new(STDOUT)
llog.level =  Logger::DEBUG
llog.debug "LE Starting"

# //////////////////////////////////////////////////////////////////////////////
mylog = Slogger::new  # The client provided STOMP callback logger

# //////////////////////////////////////////////////////////////////////////////
user =      ENV['STOMP_USER'] ? ENV['STOMP_USER'] : 'guest'
password =  ENV['STOMP_PASSWORD'] ? ENV['STOMP_PASSWORD'] : 'guestpw'
host =      ENV['STOMP_HOST'] ? ENV['STOMP_HOST'] : 'localhost'
port =      ENV['STOMP_PORT'] ? ENV['STOMP_PORT'].to_i : 61613
# //////////////////////////////////////////////////////////////////////////////
# A hash type connect *MUST* be used to enable callback logging.
# //////////////////////////////////////////////////////////////////////////////
hash = { :hosts => [ 
          {:login => user, :passcode => password, :host => 'noonehome', :port => 2525},
          {:login => user, :passcode => password, :host => host, :port => port},
          ],
          :logger => mylog,	# This enables callback logging!
          :max_reconnect_attempts => 5,
        }

# //////////////////////////////////////////////////////////////////////////////
# For a Connection:
conn = Stomp::Connection.new(hash)
conn.disconnect
# //////////////////////////////////////////////////////////////////////////////
llog.debug "LE Connection processing complete"

# //////////////////////////////////////////////////////////////////////////////
# For a Client:
conn = Stomp::Client.new(hash)
conn.close
# //////////////////////////////////////////////////////////////////////////////
# llog.debug "LE Client processing complete"

# //////////////////////////////////////////////////////////////////////////////
llog.debug "LE Ending"

