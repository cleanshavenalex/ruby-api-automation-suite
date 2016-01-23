module HttpHelpers
  def get(path, params, headers={})
    unless params.empty?
      if path.include?('?')
        path = path + '&' + params.to_query
      else
        path = path + '?' + params.to_query
      end
    end

    request = Net::HTTP::Get.new(path, headers)
    request_with_retry(request)
  end

  def post(path, params, headers={})
    headers['Content-Type'] = 'application/x-www-form-urlencoded' if headers.empty?
    request = Net::HTTP::Post.new(path, headers)
    request_with_retry(request, params.to_query)
  end

  def post_with_basic_auth(path, username, password, params, headers={})
    headers['Content-Type'] = 'application/x-www-form-urlencoded' if headers.empty?
    request = Net::HTTP::Post.new(path, headers)
    request.basic_auth(username, password)
    request_with_retry(request, params.to_query)
  end

  def post_with_json(path, params, headers={})
    headers['Content-Type'] = 'application/json' if headers.empty?
    request = Net::HTTP::Post.new(path, headers)
    request_with_retry(request, params.to_json)
  end

  def post_multipart_file(path, params, file, headers={})
    unless params.empty?
      if path.include?('?')
        path = path + '&' + params.to_query
      else
        path = path + '?' + params.to_query
      end
    end

    begin
      csv = File.open(file)
    rescue Errno::ENOENT
      csv = StringIO.new(file)
    end

    params = {
      'file' => UploadIO.new(csv, 'text/csv', 'test.csv')
    }

    request = Net::HTTP::Post::Multipart.new(path, params, headers)
    request_with_retry(request)

    csv.close
  end

  def put(path, params, headers={})
    request = Net::HTTP::Put.new(path, headers)
    request_with_retry(request, params.to_query)
  end

  def put_file(path, params, file, headers={})
    unless params.empty?
      if path.include?('?')
        path = path + '&' + params.to_query
      else
        path = path + '?' + params.to_query
      end
    end

    request = Net::HTTP::Put.new(path, headers)
    request_with_retry(request, file)
  end

  def put_with_json(path, params, data, headers={})
    unless params.empty?
      if path.include?('?')
        path = path + '&' + params.to_query
      else
        path = path + '?' + params.to_query
      end
    end

    request = Net::HTTP::Put.new(path, headers)
    request_with_retry(request, data.to_json)
  end

  def delete(path, params, headers={})
    unless params.empty?
      if path.include?('?')
        path = path + '&' + params.to_query
      else
        path = path + '?' + params.to_query
      end
    end

    request = Net::HTTP::Delete.new(path, headers)
    request_with_retry(request)
  end

  # Stole this and modified from StackOverflow:
  # http://stackoverflow.com/questions/2772778/parse-string-as-if-it-were-a-querystring-in-ruby-on-rails
  # I don't think this works for arrays and hashes in a query string
  def parse_query_string(query)
    Hash[CGI.parse(query).map {|key,values| [key, values[0]]}]
  end

  def preserve_original_http new_host, &block
    original_http = @http
    assign_http(new_host)

    return_value = block.call if block

    @http = original_http
    return_value
  end

  private

  # Pass all requests through this method to retry the call on a server error response
  # First attempt is the initial call, attempt 2 is the retry
  def request_with_retry(request, body=nil, attempts=2, time=10)
    loop do
      if debug
        puts "\n####"
        puts "## Making #{request.method} request to #{@http.address + request.path}"
        puts "## Request body: #{body}" if body
      end
      @response = @http.request(request, body)
      @parsed_response = JSON.parse(@response.body) rescue nil
      if debug
        puts "## Response code: #{@response.code}"
        if debug == "verbose"
          puts "## Response body: #{@response.body}"
        elsif @parsed_response &&
              Hash === @parsed_response &&
              @parsed_response["message"]
          puts "## Error message: #{@parsed_response["message"]}"
        end
      end
      break unless @response.code =~ /^5\d{2}$/

      attempts -= 1
      break if attempts.zero?

      if debug
        puts "## Retries remaining: #{attempts}, pausing #{time} seconds."
      else
        print 'R'
      end

      sleep(time)
    end
    @parsed_response
  end

  def assign_http(host)
    uri = URI(Common.get_host_name(host))
    @http = Net::HTTP.new(uri.host, uri.port)
    @http.use_ssl = true if uri.port == 443
  end

  def debug
    return @_debug if @_debug
    @_debug = ENV['DEBUG']
  end
end
