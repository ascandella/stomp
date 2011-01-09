module Stomp

  # Container class for frames, misnamed technically
  class Message
    attr_accessor :command, :headers, :body, :original

    def initialize(frame)
      # Set default empty values
      self.command = ''
      self.headers = {}
      self.body = ''
      self.original = frame
      return self if is_blank?(frame)

			# Figure out where individual parts of the frame begin and end.
			command_index = frame.index("\n")
			headers_index = frame.index("\n\n", command_index+1)
			lastnull_index = frame.rindex("\0")

			# Extract working copies of each frame part
			work_command = frame[0..command_index-1]
			work_headers = frame[command_index+1..headers_index-1]
			work_body = frame[headers_index+2..lastnull_index-1]

      # Set the frame values
      self.command = work_command
      work_headers.split("\n").map do |value|
        parsed_value = value.match /^([\w|-]*):(.*)$/
        self.headers[parsed_value[1].strip] = parsed_value[2].strip if parsed_value
      end

      body_length = -1
		
			# p self.headers
      if self.headers['content-length']
        body_length = self.headers['content-length'].to_i
        raise Stomp::Error::InvalidMessageLength if work_body.length != body_length
      end
      self.body = work_body[0..body_length]
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

