class Hash
  # Copied from Panda

  def deep_lower_camelize_keys(exclude_keys=[])
    deep_transform_keys(self) do |key|
      key_filter_tranform(key, exclude_keys) do
        key.to_s.camelize(:lower)  rescue key
      end
    end
  end

  def deep_underscore_keys(exclude_keys=[])
    deep_transform_keys(self) do |key|
      key_filter_tranform(key, exclude_keys) do
        key.to_s.underscore rescue key
      end
    end
  end

  def deep_symbolize_keys(exclude_keys=[])
    deep_transform_keys(self) do |key|
      key_filter_tranform(key, exclude_keys) do
        key.to_sym rescue key
      end
    end
  end

  def deep_stringify_keys(exclude_keys=[])
    deep_transform_keys(self) do |key|
      key_filter_tranform(key, exclude_keys) do
        key.to_s rescue key
      end
    end
  end

  def key_filter_tranform(key, exclude_keys=[])
    return key.to_s if exclude_keys.map(&:to_s).include?(key.to_s)
    yield
  end

  def deep_to_millsecond_values
    deep_transform_values(self) do |value|
      if value.is_a?(Time)
        value.to_millisecond rescue value
      elsif (value.is_a?(Date) || value.is_a?(DateTime))
        value.to_time.to_millisecond rescue value
      else
        value
      end
    end
  end

  def deep_boolean_to_integer
    deep_transform_values(self) do |value|
      if value == true
        1
      elsif value == false
        0
      else
        value
      end
    end
  end

  def deep_transform_keys(object, &block)
    case object
      when Hash
        object.each_with_object({}) do |(key, value), result|
          result[yield(key)] = deep_transform_keys(value, &block)
        end
      when Array
        object.map {|e| deep_transform_keys(e, &block) }
      else
        object
    end
  end

  def deep_transform_values(object, &block)
    case object
      when Hash
        object.each_with_object({}) do |(key, value), result|
          result[key] = deep_transform_values(yield(value), &block)
        end
      when Array
        object.map {|e| deep_transform_values(yield(e), &block) }
      else
        object
    end
  end
end
