module Stomp
  module Error
    class InvalidFormat < RuntimeError
      def message
        "Invalid message - invalid format"
      end
    end

    class InvalidMessageLength < RuntimeError
      def message
        "Invalid content length received"
      end
    end

    class PacketParsingTimeout < RuntimeError
      def message
        "Packet parsing timeout"
      end
    end
  end
end
