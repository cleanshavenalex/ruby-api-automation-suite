class SSOUser
  # http://REDACTED

  include HttpHelpers, SSOHelpers

  attr_accessor :username, :name, :email, :last_session, :csrf

  def initialize(opts={})
    @name = opts['name'] || 'TEST USER'
    @email = opts['email'] || 'some_email@xx.com'
    @username = opts['username'] || 'user'
    @password = opts['password'] || 'password'
    @sso_login_url = Common.get_host_name(opts['sso_login_url'] || Config["sso"]["host"])

    @last_session = nil
    @sso_csrf = nil

    uri = URI(@sso_login_url)
    @http = Net::HTTP.new(uri.host, uri.port)
    @http.use_ssl = true if @sso_login_url =~ /https/
  end

  def login(service=nil)
    headers = {
        'Accept-Encoding' => ''
    }

    get '/sso/login', {}, headers unless service

    headers['Content-Type'] = 'application/x-www-form-urlencoded'
    headers['Accept'] = 'application/json'

    update_sso_session(headers)

    @sso_csrf = get_sso_csrf unless service

    params = {
        'username' => @username,
        'password' => @password,
        'authenticity_token' => @sso_csrf
    }
    params['service'] = service if service

    post '/sso/login', params, headers

    @response
  end

  def logout
    headers = {
        'Accept-Encoding' => '',
        'Content-Type' => 'application/x-www-form-urlencoded',
        'Accept' => 'application/json'
    }
    params = {}

    post '/logout?started=1', params, headers

    @response
  end
end

