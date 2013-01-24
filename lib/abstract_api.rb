
# a standard class in which to keep things like low-level HTTP code.
# subclasses must set the following in their initializer:
# @host (e.g. api.cafepress.com)
# @port (e.g. 80)
class AbstractApi
  attr_accessor :protocol, :max_retries, :use_ssl, :timeout_seconds, :host, :port
  
  def initialize()
    @protocol = 'http'
    @max_retries = 3
    @use_ssl = false
    @timeout_seconds = 5
    @host = 'localhost'
    @port = 80
    @cookies = Hash.new
  end
  
  #do nothing.  meant to be overridden if there's standard stuff that goes in every request, like with cafepress and the v=3 parameter
  def inject_default_params(params)
  end
  
  #do nothing.  meant to overridden if necessary to tweak the net connection just before the request is sent
  def tweak_net_http_if_necessary(net)
  end 
  
  #do nothing.  meant to overridden if necessary to tweak the request just before the request is sent
  def tweak_request_if_necessary(request)
  end
  
  #do nothing.  meant to check for special errors and throw a standard exception if you want
  def check_for_special_response_errors(response)
  end
  
  def post_with_body(url, payload, suppress_debug_log=false, with_retry=true)
    request = Net::HTTP::Post.new("#{@protocol}://#{@host}:#{@port}/#{url}")
    request.body = payload
    if with_retry
      response = do_request_with_retry request, suppress_debug_log
    else
      response = do_request request
    end
    response
  end

  def post(url, params=Hash.new, suppress_debug_log=false, with_retry=true)
    request = Net::HTTP::Post.new("#{@protocol}://#{@host}:#{@port}/#{url}")
    inject_default_params(params)
    request.set_form_data(params)
    if with_retry
      response = do_request_with_retry request, suppress_debug_log
    else
      response = do_request request
    end
    response
  end
  
  def put(url, payload, suppress_debug_log=false, with_retry=true)
    request = Net::HTTP::Put.new("#{@protocol}://#{@host}:#{@port}/#{url}")
    request.body = payload
    if with_retry
      response = do_request_with_retry request, suppress_debug_log
    else
      response = do_request request
    end
    response
  end
  
  def delete(url, suppress_debug_log=false, with_retry=true)
    request = Net::HTTP::Delete.new("#{@protocol}://#{@host}:#{@port}/#{url}")
    if with_retry
      response = do_request_with_retry request, suppress_debug_log
    else
      response = do_request request
    end
    response
  end
  
  def get(url, params=Hash.new, suppress_debug_log=false, with_retry=true)
    inject_default_params(params)
    real_url = "#{@protocol}://#{@host}/#{url}?".concat(params.collect{|k,v| "#{k}=#{CGI::escape(v.to_s)}"}.join("&"))
    request = Net::HTTP::Get.new(real_url)
    if with_retry
      response = do_request_with_retry request, suppress_debug_log
    else
      response = do_request request, suppress_debug_log
    end
    response
  end

  def do_request_with_retry(request, suppress_debug_log=false, retry_count=1)
      if retry_count > (@max_retries + 1)
        raise "oops!  looks like we coded ourselves an infinite loop here.  Retry count is #{retry_count}"
      end
      begin
        response = do_request(request, suppress_debug_log)
        #this check is actually unnecessary because do_request makes the same check.  but having it here also makes 
        #  some kinds of unit testing easier, like when you want to simluate having a time out 
        #  and then not having a time out
        if (response_is_timeout?(response))
          raise Timeout::Error
        end        
      rescue Timeout::Error => e
        if retry_count >= @max_retries
          raise e
        else 
          Rails.logger.warn("caught exception trying to make http request, will try again: #{request.inspect}, #{e.message}")
          response = do_request_with_retry(request, suppress_debug_log, (retry_count + 1))
        end
      end
      response
  end
  
 def do_request(request, suppress_debug_log=false)
    net = Net::HTTP.new(@host, @port)
    net.use_ssl = @use_ssl
    if @use_ssl
      net.verify_mode = OpenSSL::SSL::VERIFY_PEER
      net.ca_file = 'config/curl_cacert.pem'
      net.enable_post_connection_check = true
    end
          
    if !suppress_debug_log
      #uncomment for debugging
      #TODO: use rails logger instead of stdout
      net.set_debug_output STDOUT #useful to see the raw messages going over the wire
    else 
      net.set_debug_output nil
    end
    net.read_timeout = @timeout_seconds
    net.open_timeout = @timeout_seconds
    set_cookies(request)
    tweak_net_http_if_necessary(net)
    tweak_request_if_necessary(request)
    Rails.logger.debug "making http call to #{request.path}"
    response = net.start do |http|
      http.request(request)
    end
    if (response_is_timeout?(response))
      raise Timeout::Error
    elsif (!response_is_success?(response))
      raise response.code + ":" + response.body 
    end
    check_for_special_response_errors(response)
    Rails.logger.debug "finished http call to #{request.path}"
    store_cookies response
    response
  end  

  def set_cookies(request)
    request.add_field("Cookie", @cookies.values.join("; "))
  end
    
  def store_cookies(response)
    cookies = response.get_fields("Set-Cookie")
    if cookies
      cookies.each do |cookie|
        real_cookie = cookie.split('; ')[0]
        key, value = real_cookie.split("=")
        @cookies[key] = real_cookie #yes, setting the whole cookie and not just the value
      end
    end
  end
  
  def response_is_success?(response)
    response.code.to_i > 199 && response.code.to_i < 300
  end
  
  def response_is_timeout?(response)
    response.code.to_i == 408 || response.code.to_i == 504
  end
end
