module Stomp
  module Error
    class InvalidFormat < RuntimeError
      def message
        "Invalid message - invalid format"
      end
    end

    class InvalidMessageLength < RuntimeError
      def message
        Invalid content length received
      end
    end
  end
end
