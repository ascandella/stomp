$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'test/unit'
require 'timeout'
require 'stomp'

# Helper routines
module TestBase
  def user
    ENV['STOMP_USER'] || "test"
  end
  def passcode
    ENV['STOMP_PASSCODE'] || "user"
  end
  # Get host
  def host
    ENV['STOMP_HOST'] || "localhost"
  end
  # Get port
  def port
    (ENV['STOMP_PORT'] || 61613).to_i
  end
end

