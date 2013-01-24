
class ApiResult < Hash
  def initialize(data=nil)
    super
    if data
      data.each do |key, value|
        self[key] = value
      end
    end
  end

  def methodify_key(key)
    if !self.respond_to? key
      self.class.send(:define_method, key) do
        return self[key]
      end
      self.class.send(:define_method, "#{key}=") do |val|
        self[key] = val
      end
    end  
  end
    
  def []=(key, value)
    store(key.to_sym,value)
    methodify_key key.to_sym
  end
  
  def [](key)
    value = fetch(key, nil)
    if value.class == Hash
      ApiResult.new value
    else
      value
    end
  end
end
