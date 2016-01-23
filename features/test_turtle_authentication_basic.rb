require './init'

# Tests for basic authentication scenarios

class TestTurtleAuthenticationBasic < APITest
  # gmail credentials (examples only)
  GMAIL = {
      u1: {
          user: 'xxtester@gmail.com',
          pass: 'password'
      },
      u2: {
          user: 'xxtester2@gmail.com',
          pass: 'password'
      }
  }

  def setup
    assign_http(Config["turtle"]["host"])
    @user = TurtleUser.new
  end

  ##
  # AS-7279 | location_opt_out sets correctly on create / update
  # AS-7335 | Don't update email preferences if email_opt_in param is not passed
  # AS-7332 | Return updated user email preferences in PUT '/usr' response
  # AS-7331 | Add email_opt_in support for /usr/update_by_id endpoint
  #
  # Steps:
  # 1. Verify response for new turtle user param setting, location_opt_out
  # 1. Verify response for update turtle user param setting, location_opt_out
  # 2. Verify response for update panda user param setting, location_opt_out
  def test_location_opt_out_on_create_update
    # Step 1
    count = 0
    2.times do
      assign_http(Config['turtle']['host'])

      headers = { 'Accept' => 'application/json' }

      user = TurtleUser.new

      params = {
          'user' => {
              'first_name' => user.first_name,
              'last_name' => user.last_name,
              'email' => user.email,
              'new_password' => user.password,
              'new_password_confirmation' => user.password,
              'vrid' => user.vrid,
              'terms' => '1',
              'zip_code' => '91201',
              'location_opt_out' => 0,
          },
          'app_id' => 'WEB',
      }
      params['user']['location_opt_out'] = 1 if count >= 1

      post '/usr', params, headers
      assert_response(@response, :success)
      turtle_response = @parsed_response
      user.id = turtle_response['id']
      user.cookie_id = turtle_response['cookie_id']

      # Check Dragon if @parsed_response['location_opt_out'] returns nil
      if @parsed_response['location_opt_out'].nil?
        get_dragon_user(user.id)
        assert_response(@response, :success)
        dragon_response = @parsed_response
        assert(dragon_response['locationOptOut'], "dragon response for user id: #{user.id}, missing the parameter: locationOptOut")
        if count >= 1
          assert_equal(1, @parsed_response['location_opt_out'], "dragon Response: #{dragon_response}")
        else
          assert_equal(0, @parsed_response['location_opt_out'], "dragon Response: #{dragon_response}")
        end
      else
        if count >= 1
          assert_equal(1, @parsed_response['location_opt_out'], "Turtle Response: #{turtle_response}")
        else
          assert_equal(0, @parsed_response['location_opt_out'], "Turtle Response: #{turtle_response}")
        end
      end
      assert_equal(false, @parsed_response['email_opt_in'], @parsed_response)

      # Login Oauth
      params = {
          'client_id' => user.turtle_client_id,
          'client_secret' => user.turtle_secret_key,
          'grant_type' => user.grant_type,
          'email' => user.email,
          'password' => user.password
      }

      post '/oauth/access_token', params
      assert_response(@response, :success)
      user.oauth_token = @parsed_response['access_token']

      # Step 2
      headers = {
          'Authorization' => "Bearer #{user.oauth_token}",
          'Accept' => 'application/json'
      }

      params = {
          'user' => {
              'location_opt_out' => 1
          },
          'email_opt_in' => 'true'
      }
      params['user']['location_opt_out'] = 0 if count >= 1

      put '/usr', params, headers
      assert_response(@response, :success)
      if count >= 1
        assert_equal(0, @parsed_response['location_opt_out'], @parsed_response)
      else
        assert_equal(1, @parsed_response['location_opt_out'], @parsed_response)
      end
      assert_equal(true, @parsed_response['email_opt_in'], @parsed_response)

      # Step 3
      assign_http(Config['panda']['host'])

      params = {
          'oauth_token' => user.oauth_token,
          'user' => {
              'location_opt_out' => 0
          },
          'email_opt_in' => 'false'
      }
      params['user']['location_opt_out'] = 1 if count >= 1

      post "/usr/update_by_id/#{user.id}", params
      assert_response(@response, :success)
      if count >= 1
        assert_equal(1, @parsed_response['location_opt_out'], @parsed_response)
      else
        assert_equal(0, @parsed_response['location_opt_out'], @parsed_response)
      end
      assert_equal(false, @parsed_response['email_opt_in'], @parsed_response)

      count += 1
    end
  end

  ##
  # Confirm expected response for /me endpoint using Valid/Invalid oauth_token
  #
  # Steps:
  # 1. Verify expected response for valid oauth_token
  # 2. Verify expected response for invalid oauth_token
  def test_invalid_oauth_token_response
    # Setup
    @user = setup_user({ 'email' => @user.email })

    # Step 1
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    get '/me', {}, headers
    assert_response(@response, :success)

    # Step 2
    headers = { 'Authorization' => "Bearer #{@user.cookie_id}" }

    get '/me', {}, headers
    assert_response(@response, :client_error)
  end

  ##
  # Test refresh_token provides valid oauth_token for expired oauth
  #
  # Steps:
  # 1. Verify rejected response for expired oauth_token: GET /me
  # 2. Verify successful response for the refresh_token request for new oauth_token
  # 3. Verify successful response with new oauth_token: GET /me
  def test_feature_refresh_token_for_expired_oauth_token
    # Setup
    opts = {
        'email' => @user.email,
        'expires_in' => 3
    }

    @user = setup_user(opts)

    sleep(opts['expires_in'])

    # Step 1
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    get '/me', {}, headers
    assert_response(@response, :client_error)

    # Step 2
    @user.acquire_refreshed_oauth_token

    # Step 3
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    get '/me', {}, headers
    assert_response(@response, :success)
  end

  ##
  # AS-6473 | Access token expires_in to be applied to all non-whitelisted clients
  # ~ API grant_type=password client id is not whitelisted, will expire
  #
  # Steps:
  # 1. Verify successful response for valid oauth_token that expires within seconds
  # 2. Verify rejected response for the same expired oauth_token after the timeout
  def test_feature_oauth_token_expires_in_non_whitelisted_client_ids
    # Setup
    opts = {
        'email' => @user.email,
        'expires_in' => 3
    }

    @user = setup_user(opts)

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    # Step 1
    get '/me', {}, headers
    assert_response(@response, :success)

    sleep(opts['expires_in'])

    # Step 2
    get '/me', {}, headers
    assert_response(@response, :client_error, "Expected Client Error for whitelisted client_id => #{@user.turtle_client_id} : expires_in => #{opts['expires_in']}")
  end

  ##
  # AS-6920 | Disable access_token expiration for specific clients
  # ~ internal_tools client id is whitelisted, will never expire
  #
  # Steps:
  # 1. Verify successful response for valid oauth_token that expires within seconds
  # 2. Verify successful response for the same expired oauth_token after the timeout
  def test_feature_oauth_token_expires_in_whitelist_client_ids
    # Setup
    @user = setup_user

    opts = {
        'internal_tools' => true,
        'expires_in' => 3
    }

    @internal_tools = setup_user(opts)

    headers = { 'Authorization' => "Bearer #{@internal_tools.oauth_token}" }

    # Step 1
    get "/usr/#{@user.id}", {}, headers
    assert_response(@response, :success)

    sleep(opts['expires_in'])

    # Step 2
    get "/usr/#{@user.id}", {}, headers
    assert_response(@response, :success, "Expected Success for Whitelisted client_id => #{@internal_tools.turtle_client_id} : 'expires_in' => #{opts['expires_in']}")
  end

  ##
  # Steps:
  # 1. User sign up/register - via api
  # 2. Confirm requiring login
  # 3. User logs in with grant_type = 'authorization_code' - via web view
  # 4. Confirm logged in
  # 5. User log out - via web view
  # 6. Confirm logged out
  def test_user_sign_up_login_and_logout_web_view_success
    # Step 1
    @user = TurtleUser.new({ 'external_client' => true })

    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 2
    headers = { 'Accept-Encoding' => '' }

    get '/login', {}, headers
    assert_response(@response, :success)
    assert_match(/login_form/, @response.body)

    # Step 3
    csrf = get_csrf

    params = {
        'email' => @user.email,
        'password' => @user.password,
        '_csrf' => csrf
    }

    update_session_in(headers)
    headers['Content-Type'] = 'application/x-www-form-urlencoded'

    post '/login', params, headers
  assert_response(@response, :redirect)

    # Step 4
    update_session_in(headers)
    headers['Accept'] = 'text/html'

    get '/login', {}, headers
    assert_response(@response, :success)
    assert_match(/You are logged in as/, @response.body)

    # Step 5
    post '/logout', {}, headers
    assert_response(@response, :redirect)

    # Step 6
    update_session_in(headers)

    get '/login', {}, headers
    assert_response(@response, :success)
    assert_match(/login_form/, @response.body)
  end

  ##
  # Steps:
  # 1. Login with missing csrf token, should return 403
  # 2. Login with invalid csrf token, should return 403
  # 3. Login with valid csrf token only, should return 403
  # 4. Login with updated session, but invalid csrf token, should return 403
  # 5. Login with updated session and valid csrf token, should be successful
  def test_csrf_protection_on_login
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    params = {
        'email' => @user.email,
        'password' => @user.password,
    }

    headers = {
        'Accept-Encoding' => '',
        'Content-Type' => 'application/x-www-form-urlencoded',
        'Accept' => 'application/json'
    }

    # Step 1
    post '/login', params, headers
    assert_response(@response, 403)

    # Step 2
    post '/login', params.merge('_csrf' => 'idunnolol'), headers
    assert_response(@response, 403)

    headers_encode_only = { 'Accept-Encoding' => '' }

    # Step 3
    get '/login', {}, headers_encode_only
    assert_response(@response, :success)

    params['_csrf'] = get_csrf

    post '/login', params, headers
    assert_response(@response, 403, "csrf: #{params['_csrf']}")

    # Step 4
    get '/login', {}, headers_encode_only
    assert_response(@response, :success)

    update_session_in(headers)

    params['_csrf'] = 'omgnowai'

    post '/login', params, headers
    assert_response(@response, 403)

    # Step 5
    get '/login', {}, headers_encode_only
    assert_response(@response, :success)

    update_session_in(headers)

    params['_csrf'] = get_csrf

    post '/login', params, headers
    assert_response(@response, :success)
  end

  ##
  # Steps:
  # 1. User sign up/register - via api
  # 2. User logs in with grant_type = 'authorization_code' - via api oauth
  # 3. Verify access token
  # 4. User log out with referrer - via web view
  def test_login_verify_logout_oauth_success
    # Step 1
    @user = TurtleUser.new({ 'external_client' => true })

    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 2
    turtle_response = @user.login_oauth_for_external_client('Allow')
    assert_response(turtle_response, :success)
    assert(@user.oauth_token)

    # Step 3
    turtle_response = @user.verify_oauth_token(@user.oauth_token)
    assert_response(turtle_response, :success)

    # Step 4
    referer = 'http://something.at.xx.com/path'

    logout_response = @user.logout(referer)
    assert_response(logout_response, :redirect)
    assert_equal(referer, logout_response['location'])
  end

  ##
  # Steps:
  # 1. User sign up/register - via api
  # 2. User logs in with grant_type = 'authorization_code' and grants permissions - via api oauth
  # 3. Verify access token
  # 4. User log out with referrer - via web view
  def test_login_oauth_success_for_external_client_user_grants_permission
    # Step 1
    @user = TurtleUser.new({ 'external_client' => true })

    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 2
    turtle_response = @user.login_oauth_for_external_client('Allow')
    assert_response(turtle_response, :success)

    # Step 3
    turtle_response = @user.verify_oauth_token(@user.oauth_token)
    assert_response(turtle_response, :success)

    # Step 4
    referer = 'http://something.at.xx.com/path'

    turtle_response = @user.logout(referer)
    assert_response(turtle_response, :redirect)
    assert_equal(referer, turtle_response['location'])
  end

  ##
  # Steps:
  # 1. User sign up/register - via api
  # 2. User logs in with grant_type = 'authorization_code' and denies permissions - via api oauth
  # 3. Verify Redirects to redirect_uri with error
  def test_oauth_fails_for_external_client_user_denies_permission
    # Step 1
    @user = TurtleUser.new({ 'external_client' => true })

    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 2
    turtle_response = @user.login_oauth_for_external_client('Deny')
    assert_response(turtle_response, :redirect)

    # Step 3
    expected_error = 'error=access_denied&error_description=Access+denied'
    assert_equal(expected_error, turtle_response['location'].gsub(/^.*\?/, ''))
  end

  ##
  # Steps:
  # 1. User sign up/register - via api
  # 2. User logs in with grant_type = 'authorization_code' and grants permissions - via api oauth
  # 3. Verify access token
  # 4. Remove client permission
  # 5. Verify access token fails
  def test_user_remove_client_permission_client_cannot_access_user_information
    skip('Skipped, see comments AS-6453')
    # sawdust zcat prod.turtle access 201503 | grep DELETE /client_permission

    # Step 1
    @user = TurtleUser.new({ 'external_client' => true })

    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 2
    turtle_response = @user.login_oauth_for_external_client('Allow')
    assert_response(turtle_response, :success)

    # Step 3
    turtle_response = @user.verify_oauth_token(@user.oauth_token)
    assert_response(turtle_response, :success)

    # Step 4
    turtle_response = @user.remove_client_permissions
    assert_response(turtle_response, :success)

    # Step 5
    turtle_response = @user.verify_oauth_token(@user.oauth_token)
    assert_response(turtle_response, :client_error)
  end

  ##
  # Steps:
  # 1. User sign up/register - via api
  # 2. User logs in with grant_type = 'password' - via api oauth - MOBILE LOGIN
  # 3. Verify access token
  def test_login_mobile
    # Step 1
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 2
    params = {
        'client_id' => @user.turtle_client_id,
        'client_secret' => @user.turtle_secret_key,
        'grant_type' => @user.grant_type,
        'email' => @user.email,
        'password' => @user.password
    }

    post '/oauth/access_token', params
    assert_response(@response, :success)
    assert(@parsed_response['access_token'].present?)

    # Step 3
    turtle_response = @user.verify_oauth_token(@parsed_response['access_token'])
    assert_response(turtle_response, :success)
  end

  ##
  # Steps:
  # 1. Deleted User logs in with grant_type = 'password' - via api oauth - MOBILE LOGIN
  # 2. Verify login returns errors
  def test_login_mobile_deleted_user
    # Step 1
    params = {
        'client_id' => @user.turtle_client_id,
        'client_secret' => @user.turtle_secret_key,
        'grant_type' => @user.grant_type,
        'email' => 'deleted_user@mailinator.com',
        'password' => 'asdfjkl;'
    }

    post '/oauth/access_token', params
    assert_response(@response, :client_error)

    # Step 2
    expected_response = {
        'error' => 'access_denied',
        'error_description' => 'Access denied: This account has been blocked.',
        'error_reason' => 'deleted_user'
    }

    turtle_response = JSON.parse(@response.body)
    assert_equal(expected_response['error'], turtle_response['error'])
    assert_equal(expected_response['error_description'], turtle_response['error_description'])
    assert_equal(expected_response['error_reason'], turtle_response['error_reason'])
  end

  ##
  # Steps:
  # 1. Sign up user
  # 2. Test wrong email token
  # 3. Acquire email token
  # 4. Confirm email
  # 5. Check verified value
  def test_confirm_email
    # Step 1
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 2
    get '/confirm_email/em_token_123456', {}
    assert_response(@response, 404)

    # Step 3
    assign_http(Config["panda"]["host"])

    params = { 'email' => @user.email }

    get '/usr', params
    assert_response(@response, :success)
    assert(@parsed_response.first['email_token'], @parsed_response)

    email_token = @parsed_response.first['email_token']

    # Step 4
    assign_http(Config["turtle"]["host"])

    get "/confirm_email/#{email_token}", {}
    assert_response(@response, :success)

    # Step 5
    assign_http(Config["panda"]["host"])

    params = { 'email' => @user.email }

    get '/usr', params
    assert_response(@response, :success)
    assert_equal(true, @parsed_response.first['verified'], @parsed_response)
  end

  ##
  # Steps:
  # 1. Existing user requests to  password
  # 2. User clicks on reset password link from the email
  # 3. User chooses a new but invalid password
  # 4. User chooses a new and valid password
  # 5. User should be able to log in with the new password
  def test_reset_password
    GmailHelpers.clear_inbox(GMAIL[:u2][:user], GMAIL[:u2][:pass])

    @user = TurtleUser.new({ 'email' => GMAIL[:u2][:user],
                             'password' => GMAIL[:u2][:pass] })

    # We're going to switch between two passwords
    # Need to first check which password the account is using so
    # we can determine which password it should try to change to
    turtle_response = @user.login
    if turtle_response.code =~ /^2\d{2}$/
      new_password = 'asdfjkl'
    else
      @user.password = 'asdfjkl'
      turtle_response = @user.login
      assert_response(turtle_response, :success)
      new_password = 'asdfjklnew'
    end

    turtle_response = @user.logout
    assert_response(turtle_response, :redirect)

    # Step 1
    turtle_response = @user.request_password_reset(@user.email)
    assert_response(turtle_response, :success)

    # Step 2
    reset_link = get_tmail_link_from_gmail(GMAIL[:u2][:user], GMAIL[:u2][:pass], APITest::EMAIL_REGEX[:password_reset])
    assert(reset_link, 'Missing reset link for password reset.')

    @user.password_token = get_password_token_from_email_link(reset_link)
    assert(@user.password_token, 'Expected token for password reset.')

    params = { 'token' => @user.password_token }

    get '/reset_password', params
    assert_response(@response, :success, 'Error requesting password reset.')
    assert_match(/\/reset_password/, @response.body)

    # Step 3
    turtle_response = @user.reset_password('a')
    assert(turtle_response, 'There was no password token.')
    assert_response(turtle_response, :client_error)

    # Step 4
    turtle_response = @user.reset_password(new_password)
    assert(turtle_response, 'There was no password token.')
    assert_response(turtle_response, :success)

    # Step 5
    turtle_response = @user.login
    assert_response(turtle_response, :success)
  end

  ##
  # Steps:
  # 1. Confirm Deleted User Cannot Login
  def test_deleted_user_cannot_login_oauth
    # Step 1
    @user = TurtleUser.new({ 'email' => 'deleted_user@mailinator.com',
                             'password' => 'asdfjkl;' })

    turtle_response = @user.login
    assert_response(turtle_response, :client_error)
    assert_match(/This account has been blocked/, turtle_response.body)
  end

  ##
  # Steps:
  # 1. Load login page and get CSRF
  # 2. Attempt to login fails
  def test_deleted_user_login_web_view
    # Step 1
    @user = TurtleUser.new({ 'email' => 'deleted_user@mailinator.com',
                             'password' => 'asdfjkl;' })

    turtle_response = @user.login
    assert_response(turtle_response, :client_error)
  end

  ##
  # Test verification email is sent for new registered user
  #
  # Steps:
  # Setup: make certain the test email is a fresh account
  # 1. User registers does not verify account
  # 2. Verify both Panda & Turtle display the same unverified flag
  # 3. Verify email received and accurate
  def test_verification_email_sent_for_new_user
    # Setup
    assign_http(Config["panda"]["host"])

    params = { 'email' => GMAIL[:u1][:user] }

    get '/usr/lookup', params
    if @response.code =~ /^2\d{2}$/
      turtle_user = TurtleUser.new(params)
      turtle_response = turtle_user.login
      assert_response(turtle_response, :success)
      turtle_response = turtle_user.login_oauth
      assert_response(turtle_response, :success)
      assert(turtle_user.oauth_token, "Expected user to have an oauth_token, but it didn't.")

      assign_http(Config["turtle"]["host"])

      params = {
          'new_email' => Common.generate_email,
          'old_email' => GMAIL[:u1][:user]
      }

      headers = { 'Authorization' => "Bearer #{turtle_user.oauth_token}" }

      put '/update_email', params, headers
      assert_response(@response, :success)
    end

    GmailHelpers.clear_inbox(GMAIL[:u1][:user], GMAIL[:u1][:pass])

    # Step 1
    assign_http(Config["turtle"]["host"])

    opts = { 'email' => GMAIL[:u1][:user] }

    @user = TurtleUser.new(opts)
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 2
    lookup_user_by_email(@user.email)
    assert_equal(false, @parsed_response['verified'], @parsed_response)

    @user.login_oauth
    refute_nil(@user.oauth_token)

    get_user_info(@user.oauth_token)
    assert_equal(0, @parsed_response['verified'], @parsed_response)

    # Step 3
    verification_link = get_yp_link_from_external_email(:register, GMAIL[:u1][:user], GMAIL[:u1][:pass])
    assert(verification_link, 'There was no account verification email.')
  end

  ##
  # AS-6893 | Restrict number of unauthorised password change attempts
  #
  # Steps:
  # 1. Create user
  # 2. Update password incorrect current password 10 times
  # 3. Update password on the 11th time throws MaxLoginAttemptsError
  def test_update_password_locks_user_after_10_failed_attempts
    # Step 1
    @user = setup_user

    # Step 2
    params = {
      'new_password' => 'hi-im-hacking-your-password',
      'new_password_confirmation' => 'hi-im-hacking-your-password',
      'old_password' => 'this-is-totally-my-password'
    }

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    10.times do
      put '/update_password', params, headers
      assert_equal('401', @response.code)
      assert_equal('Unauthorized', @parsed_response["error"])
    end

    # Step 3
    put '/update_password', params, headers
    assert_equal('403', @response.code)
    assert_equal('MaxLoginAttemptsError', @parsed_response["error"])
  end

  ##
  # AS-7383 | Change error message on empty new email field in Profile
  #
  # Steps
  # Setup
  # 1. Get user info: GET /me
  # 2. Verify error response when updating email with blank new email: PUT /update_email
  # 3. Verify successful response when updating email with new email: PUT /update_email
  def test_email_update_error_on_empty_email
    # Setup
    @user = setup_user

    # Step 1
    get_user_info(@user.oauth_token)
    assert_response(@response, :success)
    assert_equal(@user.email, @parsed_response['email'])

    # Step 2
    params = {
        'new_email' => '',
        'old_email' => @user.email
    }

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    put '/update_email', params, headers
    assert_response(@response, :client_error)
    assert_equal('InvalidParamsError', @parsed_response['error'])
    assert_equal('Email address must not be blank', @parsed_response['message'])

    # Step 3
    new_email = Common.generate_email

    params = {
        'new_email' => new_email,
        'old_email' => @user.email
    }

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    put '/update_email', params, headers
    assert_response(@response, :success)
    assert_equal(new_email, @parsed_response['email'])
  end
end
