class TurtleUser
  include HttpHelpers, GmailHelpers, TurtleHelpers

  attr_accessor :email, :email_token, :password, :turtle_url, :oauth_token, :vrid,
                :verified, :id, :turtle_client_id, :turtle_secret_key, :grant_type,
                :last_session, :cookie_id, :first_name, :last_name, :display_name,
                :app_id, :zip_code, :refresh_token, :password_token, :promo_id

  @@all_test_ids = []

  def self.all_test_ids
    @@all_test_ids.uniq
  end

  def initialize(opts={})
    @first_name = opts['first_name'] || 'As'
    @last_name = opts['last_name'] || 'Test'
    @email = opts['email'] || Common.generate_email
    @password = opts['password'] || 'password'
    @turtle_url = Common.get_host_name(opts['turtle_url'] || Config['turtle']['host'])
    @vrid = @email.slice(0, @email.index('@'))
    @location_opt_out = opts['location_opt_out'] || 0

    # Additional Register & Login options
    @app_id = opts['app_id']
    @zip_code = opts['zip_code']
    @promo_id = opts['promo_id']
    @email_opt_in = opts['email_opt_in']

    # Supported Grant Types:
    # authorization_code, client_credentials, password
    if opts['external_client']
      @turtle_client_id = Config['turtle']['external_client_id']
      @turtle_secret_key = Config['turtle']['external_secret_key']
      @grant_type = 'authorization_code'
    elsif opts['internal_tools']
      @turtle_client_id = Config['turtle']['internal_client_id']
      @turtle_secret_key = Config['turtle']['internal_secret_key']
      @grant_type = 'client_credentials'
    else
      @turtle_client_id = Config['turtle']['client_id']
      @turtle_secret_key = Config['turtle']['secret_key']
      @grant_type = opts['grant_type'] || 'password'
    end

    @last_session = nil
    @email_token = nil
    @verified = false
    @csrf = nil
    @password_token = nil

    # Oauth Specific:
    @oauth_token = nil
    @refresh_token = nil

    uri = URI(@turtle_url)
    @http = Net::HTTP.new(uri.host, uri.port)
    @http.use_ssl = true if @turtle_url =~ /https/
  end

  def register(with_vrid=true, with_json=true)
    headers = if with_json
                { 'Accept' => 'application/json' }
              else
                { 'Accept' => 'text/html' }
              end

    # for web view to kick off sessions for errors
    unless with_json
      get '/register', {}, headers

      update_session_in(headers)
    end

    params = {
        'user' => {
            'first_name' => @first_name,
            'last_name' => @last_name,
            'email' => @email,
            'new_password' => @password,
            'new_password_confirmation' => @password,
            'terms' => '1',
            'location_opt_out' => @location_opt_out,
        },
    }

    params['user']['zip_code'] = @zip_code if @zip_code
    params['vrid'] = @vrid if with_vrid
    params['app_id'] = @app_id if @app_id
    params['email_opt_in'] = @email_opt_in if @email_opt_in
    params['promo_id'] = @promo_id if @promo_id

    headers['Accept'] = 'application/json' if with_json

    post '/usr', params, headers
    if @response.code =~ /^2\d{2}$/ && with_json
      @id ||= @parsed_response['id']
      @cookie_id = @parsed_response['cookie_id']
      @display_name = @parsed_response['display_name']
      @verified = @parsed_response['verified']

      @@all_test_ids << @id
    end

    @response
  end

  def login(with_vrid=true, with_json=true, with_app_id=false)
    headers = {
        'Accept-Encoding' => ''
    }

    get '/login', {}, headers

    @csrf = get_csrf

    params = {
        'email' => @email,
        'password' => @password,
        '_csrf' => @csrf
    }

    params['app_id'] = @app_id if with_app_id
    params['vrid'] = @vrid if with_vrid

    update_session_in(headers)
    headers['Content-Type'] = 'application/x-www-form-urlencoded'
    headers['Accept'] = 'application/json' if with_json

    post '/login?login_attempt=1', params, headers

    @response
  end

  def login_oauth(redirect_uri=nil, expires_in=nil)
    @redirect_uri = redirect_uri if redirect_uri
    @expires_in = expires_in if expires_in

    acquire_oauth_token

    @response
  end

  def login_oauth_for_external_client(grant=nil, with_vrid=true, redirect_uri=nil)
    return nil unless @grant_type == 'authorization_code'

    @redirect_uri = redirect_uri if redirect_uri

    auth_code_oauth_steps(grant, with_vrid)

    acquire_oauth_token if grant == 'Allow'

    @response
  end

  def auth_code_oauth_steps(grant=nil, with_vrid=true)
    return if @oauth_token

    authorize_params = {
        'response_type' => 'code',
        'client_id' => @turtle_client_id
    }

    path = '/oauth/authorize'

    get path, authorize_params

    headers = { 'Accept-Encoding' => '' }

    update_session_in(headers)
    path = @response['location'].gsub(@turtle_url, '')

    # prior response redirect path is '/dialog/oauth' with authorize_params
    get path, {}, headers

    update_session_in(headers)
    path = @response['location'].gsub(@turtle_url, '')

    # prior response redirect path is '/login' and 'next=/dialog/oauth'
    get path, {}, headers

    @csrf = get_csrf

    update_session_in(headers)
    headers['Content-Type'] = 'application/x-www-form-urlencoded'

    params = {
        'email' => @email,
        'password' => @password,
        '_csrf' => @csrf
    }

    params['vrid'] = @vrid if with_vrid

    # prior response has no redirect path, using same '/login' path
    post path, params, headers

    headers.delete 'Content-Type'
    update_session_in(headers)
    path = @response['location'].gsub(@turtle_url, '')

    # prior response redirect path is '/dialog/oauth'
    get path, {}, headers

    # -- needed for Requires Permissions checkbox within client @turtle/clients --
    permissions_csrf = get_csrf(true)

    headers = {
        'Cookie' => "rack.session=#{@last_session}",
        'Accept-Encoding' => '',
    }

    params = {
        '_csrf' => permissions_csrf,
        'grant' => grant
    }

    # path should be : '/dialog/oauth?client_id=#{@turtle_client_id}&response_type=code'
    post path, params, headers

    raise "GET #{@response.code}: #{@response.body}" unless @response['location']

    @code = @response['location'].gsub(/^.*code=/, '') if grant == 'Allow'
  end

  def remove_client_permissions
    headers = {
        'Cookie' => "rack.session=#{@last_session}",
        'X-CSRF-Token' => @csrf,
        'Accept-Encoding' => '',
        'Accept' => 'text/plain'
    }

    delete "/client_permission/#{@turtle_client_id}", {}, headers

    @response
  end

  def logout(referer=nil, redirect_uri=nil)
    headers = {}
    params = {}

    headers['Referer'] = referer if referer
    headers['Cookie'] = "rack.session=#{@last_session}" if @last_session

    params['redirect_uri'] = redirect_uri if redirect_uri
    params['access_token'] = @oauth_token if @oauth_token

    post '/logout', params, headers

    @oauth_token = nil

    @response
  end

  def acquire_oauth_token
    params = {
        'client_id' => @turtle_client_id,
        'client_secret' => @turtle_secret_key,
        'grant_type' => @grant_type
    }

    params['code'] = @code if @code
    params['redirect_uri'] = @redirect_uri if @redirect_uri
    if @grant_type == 'password'
      params['email'] = @email
      params['password'] = @password
      params['expires_in'] = @expires_in if @expires_in
    end

    path = '/oauth/access_token'

    post path, params

    raise "POST #{path} #{@response.code} #{@grant_type} : #{@response.body}" unless @parsed_response

    @refresh_token = @parsed_response['refresh_token'] if @parsed_response['refresh_token']
    @oauth_token = @parsed_response['access_token']
  end

  def acquire_refreshed_oauth_token
    return unless @refresh_token

    params = {
        'client_id' => @turtle_client_id,
        'client_secret' => @turtle_secret_key,
        'grant_type' => 'refresh_token',
        'refresh_token' => @refresh_token,
    }

    path = '/oauth/access_token'

    post path, params

    raise "POST #{path} #{@response.code} refresh_token : #{@response.body}" unless @parsed_response

    @refresh_token = @parsed_response['refresh_token'] if @parsed_response['refresh_token']
    @oauth_token = @parsed_response['access_token']
  end

  def verify_oauth_token(token)
    token ||= @oauth_token

    headers = { 'Authorization' => "Bearer #{token}" }

    get '/me', {}, headers

    @response
  end

  def request_password_reset(email=nil)
    headers = { 'Accept' => 'application/json' }

    params = { 'email' => email || @email }

    post '/forgot_password', params, headers

    @response
  end

  def reset_password(new_password)
    return unless @password_token

    headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'text/plain'
    }

    params = {
        'token' => @password_token,
        'password' => new_password
    }

    post_with_json '/reset_password', params, headers

    @password = new_password if @response.code =~ /^2\d{2}$/

    @response
  end
end
