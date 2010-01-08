require 'test/unit'
require 'timeout'
require 'stomp'
$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))
# Helper routines
module TestBase
  # Get host
  def host
    ENV['STOMP_HOST'] || "localhost"
  end
  # Get port
  def port
    (ENV['STOMP_PORT'] || 61613).to_i
  end
end

