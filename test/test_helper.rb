require 'test/unit'
require 'timeout'
require 'stomp'
$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))
# Helper routines
class TestBase < Test::Unit::TestCase
  # Get host
  def host()
    ENV['STOMP_HOST'] ? ENV['STOMP_HOST'] : "localhost"
  end
  # Get port
  def port()
    ENV['STOMP_PORT'] ? ENV['STOMP_PORT'].to_i : 61613
  end
end

