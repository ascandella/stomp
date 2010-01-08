class ::Hash
  def uncamelize_and_symbolize_keys
    self.uncamelize_and_stringify_keys.symbolize_keys
  end

  def uncamelize_and_stringify_keys
    uncamelized = {}
    self.each_pair do |key, value|
      new_key = key.to_s.split(/(?=[A-Z])/).join('_').downcase
      uncamelized[new_key] = value
    end

    uncamelized
  end

  def symbolize_keys
    symbolized = {}
    self.each_pair do |key, value|
      symbolized[key.to_sym] = value
    end

    symbolized
  end unless self.respond_to? :symbolize_keys
end