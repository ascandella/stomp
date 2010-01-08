module Stomp

  # Container class for frames, misnamed technically
  class Message
    attr_accessor :command, :headers, :body, :original

    def initialize(message)
      # Set default empty values
      self.command = ''
      self.headers = {}
      self.body = ''
      self.original = message
      return self if is_blank?(message)

      # Parse the format of the received stomp message
      parse = message.match /^(CONNECTED|MESSAGE|RECEIPT|ERROR)\n(.*)\n\n(.*)\0\n?$/m
      raise Stomp::Error::InvalidFormat if parse.nil?

      # Set the message values
      self.command = parse[1]
      self.headers = {}
      parse[2].split("\n").map do |value|
        parsed_value = value.match /^([\w|-]*):(.*)$/
        self.headers[parsed_value[1].strip] = parsed_value[2].strip if parsed_value
      end

      body_length = -1
      if self.headers['content-length']
        body_length = self.headers['content-length'].to_i
        raise Stomp::Error::InvalidMessageLength if parse[3].length != body_length
      end
      self.body = parse[3][0..body_length].chomp
    end

    def to_s
      "<Stomp::Message headers=#{headers.inspect} body='#{body}' command='#{command}' >"
    end

    def empty?
      is_blank?(command) && is_blank?(headers) && is_blank?(body)
    end

    private
      def is_blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
  end

end
