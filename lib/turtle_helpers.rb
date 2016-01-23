module TurtleHelpers
  def setup_user(opts={})
    preserve_original_http(Config['panda']['host']) do
      user = TurtleUser.new(opts)
      turtle_response = user.register
      assert_response(turtle_response, :success)
      turtle_response = user.login
      assert_response(turtle_response, :success)
      assert(user.id, turtle_response.body)

      # Get Email Token
      lookup_user_by_email(user.email)
      user.email_token = @parsed_response['email_token'] if @parsed_response['email_token']

      # Verify User
      if user.email_token
        # Users POST with promo_id auto-verifies the account
        if opts['promo_id']
          assert_equal(true, @parsed_response['verified'], @parsed_response)
        else
          assert_equal(false, @parsed_response['verified'], @parsed_response)

          assign_http(Config['turtle']['host'])

          get "/confirm_email/#{user.email_token}", {}
          assert_response(@response, :success)
        end

        if opts['redirect_uri'] && opts['expires_in']
          user.login_oauth(opts['redirect_uri'], opts['expires_in'])
        elsif opts['redirect_uri']
          user.login_oauth(opts['redirect_uri'])
        elsif opts['expires_in']
          user.login_oauth(nil, opts['expires_in'])
        else
          user.login_oauth
        end

        refute_nil(user.oauth_token, 'oauth_token is missing!')

        # Ignore Internal Tools for Turtle check
        unless opts['internal_tools']
          get_user_info(user.oauth_token)
          assert_equal(1, @parsed_response['verified'], @parsed_response)
        end

        lookup_user_by_email(user.email)
        assert_equal(true, @parsed_response['verified'], @parsed_response)

        user.verified = true
      end

      user
    end
  end

  def login_existing_user(opts={}, expect_verified=true)
    preserve_original_http(Config['panda']['host']) do
      user = TurtleUser.new(opts)
      turtle_response = user.login
      assert_response(turtle_response, :success)
      parsed_response = JSON.parse(turtle_response.body)
      user.id = parsed_response['id']
      user.cookie_id = parsed_response['cookie_id']
      user.display_name = parsed_response['display_name']

      opts['redirect_uri'] ? user.login_oauth(opts['redirect_uri']) : user.login_oauth
      refute_nil(user.oauth_token, 'oauth_token is missing!')

      # Check Existing User is Verified
      unless expect_verified
        # Ignore Internal Tools for Turtle check
        unless opts['internal_tools']
          get_user_info(user.oauth_token)
          assert_equal(1, @parsed_response['verified'], @parsed_response)
        end

        lookup_user_by_email(user.email)
        assert_equal(true, @parsed_response['verified'], @parsed_response)

        user.verified = true
      end

      user
    end
  end

  def get_user_info(oauth_token=nil, opts={})
    preserve_original_http(Config['panda']['host']) do
      return nil unless oauth_token

      assign_http(Config['turtle']['host'])

      headers = { 'Authorization' => "Bearer #{oauth_token}" }

      get '/me', opts, headers
      assert_response(@response, :success)

      @parsed_response
    end
  end

  def update_session_in(hash)
    session = CGI::Cookie.parse(@response['set-cookie'])['rack.session'].first
    if session.present?
      @last_session = CGI.escape(session)
      hash['Cookie'] = "rack.session=#{CGI.escape(session)}"
    end
  end

  def get_csrf(permission_grant=false)
    permission_grant ? form = 'form-wrapper' : form = 'login-form'

    Nokogiri::HTML(@response.body).
        css(".#{form} form input[name=_csrf]").
        attribute('value').
        content
  end
end
