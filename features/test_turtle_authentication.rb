require './init'

# Tests for advanced authentication features and scenarios

class TestTurtleAuthentication < APITest
  # gmail credentials
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
  # Steps:
  # 1. A visitor adds a shortcut to my book
  # 2. Visitor should have a shortcut in my book
  # 3. Visitor signs up and becomes a user
  # 4. User should have a shortcut without adding it
  # 5. Visitor should not have a shortcut in my book anymore
  def test_my_book_merge_with_new_user_turtle
    # Step 1
    assign_http(Config["panda"]["host"])

    params = {
        'type' => { 'shortcuts' => ['gas'] },
        'vrid' => @user.vrid
    }

    post '/mb/preferences', params
    assert_response(@response, :success)

    # Step 2
    params = {
        'type' => 'shortcuts',
        'vrid' => @user.vrid
    }

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Shortcuts'].size, @response.body)
    assert_equal('gas', @parsed_response['Shortcuts'].first['Name'])

    # Step 3
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 4
    params = {
        'type' => 'shortcuts',
        'user_id' => @user.id
    }

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Shortcuts'].size)
    assert_equal('gas', @parsed_response['Shortcuts'].first['Name'])

    # Step 5
    params = {
        'type' => 'shortcuts',
        'vrid' => @user.vrid
    }

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(0, @parsed_response['Shortcuts'].size, @response.body)
  end

  # Steps:
  # 1. User sign up/register - via api - This is a pre-requisite
  #     We create the user first to mimic the existing user behavior
  # 2. A visitor, adds a shortcut to my book
  # 3. Visitor should have a shortcut in my book
  # 4. User logs in with grant_type = 'authorization_code' - via api oauth
  # 5. Confirm merged data
  # 6. Visitor should not have a shortcut in my book anymore
  def test_my_book_merge_with_user_login
    # Step 1
    @user = TurtleUser.new({ 'external_client' => true })

    turtle_response = @user.register(false)
    assert_response(turtle_response, :success)
    assert(@user.id)

    # Step 2
    assign_http(Config["panda"]["host"])

    params = {
        'type' => { 'shortcuts' => ['gas'] },
        'vrid' => @user.vrid
    }

    post '/mb/preferences', params
    assert_response(@response, :success)

    # Step 3
    params = {
        'type' => 'shortcuts',
        'vrid' => @user.vrid
    }

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Shortcuts'].size, @response.body)
    assert_equal('gas', @parsed_response['Shortcuts'].first['Name'])

    # Step 4
    turtle_response = @user.login_oauth_for_external_client('Allow')
    assert_response(turtle_response, :success)
    assert(@user.oauth_token)

    # Step 5
    params = {
        'type' => 'shortcuts',
        'oauth_token' => @user.oauth_token,
        'uvrid' => @user.vrid
    }

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Shortcuts'].size)
    assert_equal('gas', @parsed_response['Shortcuts'].first['Name'])

    # Step 6
    params = {
        'type' => 'shortcuts',
        'vrid' => @user.vrid
    }

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(0, @parsed_response['Shortcuts'].size, @response.body)
  end

  ##
  # Steps:
  # 1. User sign up/register - via api
  # 2. Search for a business
  # 3. Add a review
  # 4. Add an image to business
  # 5. Check that image and review isn't visible except in profile
  # 6. Verify user
  # 7. Check that the image and review is public on multiple endpoints
  # 8. Hide image
  # 9. Hide review
  def test_unverified_user_merge_ugc
    # Step 1
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert @user.id
    turtle_response = @user.login_oauth
    assert_response(turtle_response, :success)
    assert @user.oauth_token

    # Step 2
    opts =  {
        'vrid' => @user.vrid,
        'app_id' => 'WEB',
        'ptid' => 'API'
    }

    sr_check = nil
    start_time = Time.now
    query = ['sushi bars','attorneys','plumbers'].sample
    location = 'los angeles, ca'
    while sr_check.nil? && Time.now - start_time < 10
      get_consumer_search_resp(query, location, opts)
      assert_response(@response, :success)
      sr_check = @parsed_response['SearchResult']['BusinessListings'].first
    end

    listings = []
    @parsed_response['SearchResult']['BusinessListings'].each do |business|
      if business['Rateable'] == 1 && business['Int_Xxid']
        listings << business
      end
    end
    refute_empty(listings, "No Rateable listings returned for: #{query}, #{location}")
    listing = listings.sample
    int_xxid = listing['Int_Xxid']

    # Step 3
    response_check = nil
    start_time = Time.now

    while response_check !~ /^2\d{2}$/ && Time.now - start_time < 10
      params = {
          'int_xxid' => int_xxid,
          'source' => 'xx',
          'subject' => 'this is test',
          'body' => 'this is user rating test test test test',
          'value' => 3,
          'oauth_token' => @user.oauth_token
      }

      assign_http(Config["panda"]["host"])

      post '/rats/add_rating', params
      response_check = @response.code
    end

    assert(@parsed_response['RatingID'].present?, 'RatingID not set')
    rating_id = @parsed_response['RatingID']

    # Step 4
    assign_http(Config["monkey"]["host"])

    headers = { 'Content-Type' => 'image/jpg' }

    params = {
        'api_key' => Config["monkey"]["api_key"],
        'oauth_token' => @user.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    put_file '/b_image', params, generate_random_image, headers
    assert_response(@response, :success)
    assert(@parsed_response['id'], @parsed_response)
    sha1 = @parsed_response['id']

    params = {
        'ext_type' => 'int_xxid',
        'ext_id' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'api_key' => Config["monkey"]["api_key"],
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    post "/b_image/#{sha1}", params
    assert_response(@response, :success)

    # Step 5
    refute_image_in_consumer_business(sha1, listing)
    assert_image_in_profile(sha1, @user)
    refute_rating_in_listing(rating_id, listing)
    assert_rating_in_profile(rating_id, @user)

    assign_http(Config["panda"]["host"])

    get "/rats/#{rating_id}", {}
    assert_response(@response, :success)
    assert_equal(rating_id, @parsed_response['id'])
    assert_equal(int_xxid, @parsed_response['int_xxid'].to_s)
    assert_equal(@user.id, @parsed_response['author_user_id'])
    assert_equal(false, @parsed_response['verified'])

    # Step 6
    params = { 'email' => @user.email }

    get '/usr', params
    assert_response(@response, :success)
    assert(@parsed_response.first['email_token'], @parsed_response)
    email_token = @parsed_response.first['email_token']

    assign_http(Config["turtle"]["host"])

    get "/confirm_email/#{email_token}", {}
    assert_response(@response, :success)

    # Step 7
    assert_image_in_consumer_business(sha1, listing)
    assert_image_in_profile(sha1, @user)
    assert_rating_in_listing(rating_id, listing)
    assert_rating_in_profile(rating_id, @user)

    assign_http(Config["panda"]["host"])

    get "/rats/#{rating_id}", {}
    assert_response(@response, :success)
    assert_equal(rating_id, @parsed_response['id'])
    assert_equal(int_xxid, @parsed_response['int_xxid'].to_s)
    assert_equal(@user.id, @parsed_response['author_user_id'])
    assert_equal(true, @parsed_response['verified'])

    # Step 8
    assign_http(Config["monkey"]["host"])

    params = {
        'ext_type' => 'int_xxid',
        'ext_id' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'api_key' => Config["monkey"]["api_key"],
        'reason' => 6
    }

    post "/b_image/#{sha1}/int_xxid/#{int_xxid}/report", params
    assert_response(@response, :success)
    refute_nil(@parsed_response['image_path'], @parsed_response)
    params = { 'api_key' => Config["monkey"]["api_key"] }

    get "/business/images/#{int_xxid}", params
    assert_response(@response, :success)
    refute(@parsed_response[int_xxid].map { |images| images['id'] }.include?(sha1), 'Image still found in list after delete.') unless @parsed_response.blank?

    # Step 9
    assign_http(Config["panda"]["host"])

    delete "/rats/#{rating_id}", {}
    assert_response(@response, :success)

    get "/rats/#{rating_id}", {}
    assert_response(@response, :client_error)
  end

  ##
  # Steps:
  # 1. User sign up, verify, and login
  # 2. Search for a business
  # 3. Add review to business
  # 4. Add image to business
  # 5. Check review and image is public on multiple endpoints
  # 6. Hide image
  # 7. Hide review
  def test_verified_user_ugc
    # Step 1
    @user = setup_user({ 'email' => @user.email })

    # Step 2
    opts =  {
        'vrid' => @user.vrid,
        'app_id' => 'WEB',
        'ptid' => 'API'
    }

    sr_check = nil
    start_time = Time.now
    query = ['sushi bars','attorneys','plumbers'].sample
    location = 'los angeles, ca'
    while sr_check.nil? && Time.now - start_time < 10
      get_consumer_search_resp(query, location, opts)
      assert_response(@response, :success)
      sr_check = @parsed_response['SearchResult']['BusinessListings'].first
    end

    listings = []
    @parsed_response['SearchResult']['BusinessListings'].each do |business|
      if business['Rateable'] == 1 && business['Int_Xxid']
        listings << business
      end
    end
    refute_empty(listings, "No Rateable listings returned for: #{query}, #{location}")
    listing = listings.sample
    int_xxid = listing['Int_Xxid']

    # Step 3
    response_check = nil
    start_time = Time.now

    while response_check !~ /^2\d{2}$/ && Time.now - start_time < 10
      params = {
          'int_xxid' => int_xxid,
          'source' => 'xx',
          'subject' => 'this is test',
          'body' => 'API TEST -- This is the best rating in the worlds!',
          'value' => 4,
          'oauth_token' => @user.oauth_token
      }

      assign_http(Config["panda"]["host"])

      post '/rats/add_rating', params
      response_check = @response.code
    end

    assert(@parsed_response['RatingID'].present?, 'RatingID not set')
    rating_id = @parsed_response['RatingID']

    # Step 4
    assign_http(Config["monkey"]["host"])

    headers = { 'Content-Type' => 'image/jpg' }

    params = {
        'api_key' => Config["monkey"]["api_key"],
        'oauth_token' => @user.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    put_file('/b_image', params, generate_random_image, headers)
    assert_response(@response, :success)
    assert(@parsed_response['id'], @parsed_response)
    sha1 = @parsed_response['id']

    params = {
        'ext_type' => 'int_xxid',
        'ext_id' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'api_key' => Config["monkey"]["api_key"],
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    post "/b_image/#{sha1}", params
    assert_response(@response, :success)

    # Step 5
    assert_image_in_consumer_business(sha1, listing)
    assert_image_in_profile(sha1, @user)
    assert_rating_in_listing(rating_id, listing)
    assert_rating_in_profile(rating_id, @user)

    assign_http(Config["panda"]["host"])

    get "/rats/#{rating_id}", {}
    assert_response(@response, :success)
    assert_equal(rating_id, @parsed_response['id'])
    assert_equal(int_xxid, @parsed_response['int_xxid'].to_s)
    assert_equal(@user.id, @parsed_response['author_user_id'])
    assert_equal(true, @parsed_response['verified'])

    # Step 6
    assign_http(Config["monkey"]["host"])

    params = {
        'ext_type' => 'int_xxid',
        'ext_id' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'api_key' => Config["monkey"]["api_key"],
        'reason' => 6
    }

    post "/b_image/#{sha1}/int_xxid/#{int_xxid}/report", params
    assert_response(@response, :success)
    refute_nil(@parsed_response['image_path'], @parsed_response)
    params = { 'api_key' => Config["monkey"]["api_key"] }

    get "/business/images/#{int_xxid}", params
    assert_response(@response, :success)
    refute(@parsed_response[int_xxid].map { |images| images['id'] }.include?(sha1), 'Image still found in list after delete.') unless @parsed_response.blank?

    # Step 7
    assign_http(Config["panda"]["host"])

    delete "/rats/#{rating_id}", {}
    assert_response(@response, :success)

    get "/rats/#{rating_id}", {}
    assert_response(@response, 404)
  end

  ##
  # AS-6235 | Prevent /login and /forgot_password from 500ing
  #
  # Steps:
  # 1. Confirm error response from forgot_password for email with null characters
  # 2. Confirm error response from login for email with null characters
  def test_forgot_password_and_login_with_email_containing_null_bytes
    # Setup
    null_character_email = "bob\00@mailinator.com"
    @user = TurtleUser.new({ 'email' => null_character_email })

    # Step 1
    headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }

    params = { 'email' => null_character_email }

    post '/forgot_password', params, headers
    assert_response(@response, :client_error)
    assert_equal('InvalidParamsError', @parsed_response['error'], @parsed_response)
    assert_equal('Null bytes are not allowed in data', @parsed_response['message'], @parsed_response)

    # # Step 2
    @user.login
    assert_response(@response, :client_error)
    assert_equal('InvalidParamsError', @parsed_response['error'], @parsed_response)
    assert_equal('Null bytes are not allowed in data', @parsed_response['message'], @parsed_response)
  end

  ##
  # AS-6897 | Verified user changing email should not adjust verified flag
  #
  # Steps:
  # Setup: make certain the test email is a fresh account
  # 1. User registers doesnt verify account
  # 2. Verify both Panda & Turtle display the same unverified flag
  # 3. User updates email for unverified account
  # 4. Verify both Panda & Turtle display the same unverified flag
  # 5. User registers and verified account
  # 6. Verify both Panda & Turtle display the same verified flag
  # 7. User updates email for verified account
  # 8. Verify both Panda & Turtle display the same verified flag
  def test_user_updating_email_doesnt_change_verified_state
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
    assign_http(Config["turtle"]["host"])

    new_email = Common.generate_email

    params = {
        'new_email' => new_email,
        'old_email' => @user.email
    }

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    put '/update_email', params, headers
    assert_response(@response, :success)

    @user.email = new_email

    # Step 4
    lookup_user_by_email(@user.email)
    assert_equal(false, @parsed_response['verified'], @parsed_response)

    get_user_info(@user.oauth_token)
    assert_equal(0, @parsed_response['verified'], @parsed_response)

    # step 5
    GmailHelpers.clear_inbox(GMAIL[:u1][:user], GMAIL[:u1][:pass])

    @user = setup_user({ 'email' => GMAIL[:u1][:user] })

    verification_link = get_link_from_external_email(:register, GMAIL[:u1][:user], GMAIL[:u1][:pass])
    assert(verification_link, 'There was no account verification email.')

    # Step 6
    lookup_user_by_email(GMAIL[:u1][:user])
    assert_equal(true, @parsed_response['verified'], @parsed_response)

    get_user_info(@user.oauth_token)
    assert_equal(1, @parsed_response['verified'], @parsed_response)

    # Step 7
    new_email = Common.generate_email

    params = {
        'new_email' => new_email,
        'old_email' => GMAIL[:u1][:user]
    }

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    put '/update_email', params, headers
    assert_response(@response, :success)

    @user.email = new_email

    # Step 8
    lookup_user_by_email(@user.email)
    assert_equal(true, @parsed_response['verified'], @parsed_response)

    get_user_info(@user.oauth_token)
    assert_equal(1, @parsed_response['verified'], @parsed_response)
  end

  ##
  # AS-5588 | Test Internal Client Reset Password Token
  # endpoint: post '/reset_password_token'
  #
  # Steps:
  # 1. Internal tools requests password reset through specific endpoint
  # 2. Validate Response for Endpoint
  def test_internal_tools_reset_password_token
    # Step 1
    @internal_tools = setup_user({ 'internal_tools' => true })
    @user = setup_user({ 'email' => @user.email })

    headers = {
        'Authorization' => "Bearer #{@internal_tools.oauth_token}",
        'Accept' => 'application/json'
    }

    params = { 'email' => @user.email }

    # Step 2
    post '/reset_password_token', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['token'])
  end

  ##
  # AS-4960 | Test all endpoints with grant type as client_credentials
  # endpiont: get, put, delete '/usr/:id'
  #
  # Steps:
  # 1. Validate response to valid token when internal_tools client requests User's information
  # 2. Validate response to invalid token when non-internal_tools client requests User's information
  # 3. Validate response to valid token when internal_tools client updates User's information
  # 4. Validate response to invalid token when non-internal_tools client attempts to update User's information
  # 5. Validate response to invalid token when non-internal_tools client attempts to delete the User
  # 6. Validate response to valid token when internal_tools client deletes User
  def test_internal_tools_endpoint_users_id
    # Step 1
    @internal_tools = setup_user({ 'internal_tools' => true })
    @user = setup_user({ 'email' => @user.email })

    headers = { 'Authorization' => "Bearer #{@internal_tools.oauth_token}" }

    get "/usr/#{@user.id}", {}, headers
    assert_response(@response, :success)
    assert_equal(@user.id, @parsed_response['id'],
                 "Expected user id '#{@user.id}' does not match the Response : '#{@parsed_response['id']}'")

    # Step 2
    fail_headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    get "/usr/#{@user.id}", {}, fail_headers
    assert_response(@response, :client_error)
    assert_match(/InvalidClientError/, @response.body, @parsed_response)

    # Step 3
    params = {
        'user' => {
            'first_name' => 'Jimmy',
            'last_name' => 'Stuart',
            'email' => Common.generate_email,
            'new_password' => 'pa$$word_1',
            'new_password_confirmation' => 'pa$$word_1'
        }
    }

    put "/usr/#{@user.id}", params, headers
    assert_response(@response, :success)
    assert_equal(params['user']['first_name'], @parsed_response['first_name'], "Expected first name '#{params['user']['first_name']}'
                 does not match the Response : '#{@parsed_response['first_name']}'")
    assert_equal(params['user']['last_name'], @parsed_response['last_name'], "Expected last name '#{params['user']['last_name']}'
                 does not match the Response : '#{@parsed_response['last_name']}'")
    assert_equal(params['user']['email'], @parsed_response['email'], "Expected last name '#{params['user']['email']}'
                 does not match the Response : '#{@parsed_response['email']}'")

    # Step 4
    put "/usr/#{@user.id}", params, fail_headers
    assert_response(@response, :client_error)
    assert_match(/InvalidClientError/, @response.body, @parsed_response)

    # Step 5
    delete "/usr/#{@user.id}", params, fail_headers
    assert_response(@response, :client_error)
    assert_match(/InvalidClientError/, @response.body, @parsed_response)

    # Step 6
    delete "/usr/#{@user.id}", params, headers
    assert_response(@response, :success)
  end

  ##
  # AS-4960 | Test all endpoints with grant type as client_credentials
  # endpiont: get '/usr'
  #
  # Steps:
  # 1. Validate response to valid token when internal_tools client requests Users information
  # 2. Validate response to invalid token when non-internal_tools client requests Users information
  def test_internal_tools_endpoint_users
    # Step 1
    @internal_tools = setup_user({ 'internal_tools' => true })
    @user1 = setup_user({'email' => @user.email})
    @user2 = setup_user
    @user3 = setup_user
    @user4 = setup_user
    @user5 = setup_user

    headers = { 'Authorization' => "Bearer #{@internal_tools.oauth_token}" }

    params = { 'ids' => [@user1.id, @user2.id, @user3.id, @user4.id, @user5.id] }

    get '/usr', params, headers
    assert_response(@response, :success)
    params['ids'].each do |user_id|
      assert_equal(user_id, @parsed_response["#{user_id}"]['id'])
    end

    # Step 2
    #non-internal tools oauth
    fail_headers = { 'Authorization' => "Bearer #{@user1.oauth_token}" }

    get '/usr', params, fail_headers
    assert_response(@response, :client_error)
    assert_match(/InvalidClientError/, @response.body, @parsed_response)
  end

  ##
  # AS-6206 | Authorization Code support for Cosmos
  #
  # Steps:
  # Setup
  # 1. Internal client requests auth code for user
  # 2. User authenticates using auth code returned
  # 3. Internal client requests auth code for user with overrides
  # 4. User authenticates using auth code returned with overrides
  # 5. Internal client requests auth code for user with multiple scopes
  # 6. User authenticates using auth code returned with multiple scopes
  def test_authorization_code_for_internal_tools
    # Setup
    @internal_tools = setup_user({ 'internal_tools' => true })
    @user1 = setup_user({'email' => @user.email})
    @user2 = setup_user
    @user3 = setup_user

    # Step 1
    headers = { 'Authorization' => "Bearer #{@internal_tools.oauth_token}" }

    params = {
        'email' => @user1.email,
        'password' => @user1.password,
        'client_id' => @user1.turtle_client_id
    }

    post '/authorization_code', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['code'], @parsed_response)
    assert(@parsed_response['scope'], @parsed_response)
    assert(@parsed_response['redirect_uri'], @parsed_response)

    # Step 2
    params = {
        'client_id' => @user1.turtle_client_id,
        'client_secret' => @user1.turtle_secret_key,
        'grant_type' => 'authorization_code',
        'code' => @parsed_response['code'],
        'redirect_uri' => @parsed_response['redirect_uri']
    }

    post '/oauth/access_token', params
    assert_response(@response, :success)
    assert(@parsed_response['access_token'], @parsed_response)
    assert(@parsed_response['token_type'], @parsed_response)
    assert_equal(7776000, @parsed_response['expires_in'], @parsed_response)
    assert(@parsed_response['refresh_token'], @parsed_response)

    # Step 3
    params = {
        'email' => @user2.email,
        'password' => @user2.password,
        'client_id' => @user2.turtle_client_id,
        'scope' => 'foo',
        'redirect_uri' => 'https://xx.com/callback?foo=foo&bar=bar'
    }

    post '/authorization_code', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['code'], @parsed_response)
    assert_equal(params['scope'], @parsed_response['scope'], @parsed_response)
    assert_equal(params['redirect_uri'], @parsed_response['redirect_uri'], @parsed_response)

    # Step 4
    params = {
        'client_id' => @user2.turtle_client_id,
        'client_secret' => @user2.turtle_secret_key,
        'grant_type' => 'authorization_code',
        'code' => @parsed_response['code'],
        'redirect_uri' => @parsed_response['redirect_uri']
    }

    post '/oauth/access_token', params
    assert_response(@response, :success)
    assert(@parsed_response['access_token'], @parsed_response)
    assert(@parsed_response['token_type'], @parsed_response)
    assert_equal('foo', @parsed_response['scope'], @parsed_response)
    assert_equal(7776000, @parsed_response['expires_in'], @parsed_response)
    assert(@parsed_response['refresh_token'], @parsed_response)

    # Step 5
    params = {
        'email' => @user3.email,
        'password' => @user3.password,
        'client_id' => @user3.turtle_client_id,
        'scope' => 'foo bar zeta alpha',
        'redirect_uri' => 'https://xx.com/callback?foo=foo&bar=bar'
    }

    post '/authorization_code', params, headers
    assert_response(@response, :success)

    # turtle /app/model.rb sorts this within this response, /lib/dragon/models/serialization.rb does not
    sorted_scopes = params['scope'].split(' ').sort.join(' ')
    sorted_parsed_response_scopes = @parsed_response['scope'].split(' ').sort.join(' ')

    assert(@parsed_response['code'], @parsed_response)
    assert_equal(sorted_scopes, sorted_parsed_response_scopes, @parsed_response)
    assert_equal(params['redirect_uri'], @parsed_response['redirect_uri'], @parsed_response)

    # Step 6
    params = {
        'client_id' => @user3.turtle_client_id,
        'client_secret' => @user3.turtle_secret_key,
        'grant_type' => 'authorization_code',
        'code' => @parsed_response['code'],
        'redirect_uri' => @parsed_response['redirect_uri']
    }

    post '/oauth/access_token', params
    assert_response(@response, :success)
    assert(@parsed_response['access_token'], @parsed_response)
    assert(@parsed_response['token_type'], @parsed_response)
    assert_equal(sorted_scopes, @parsed_response['scope'], @parsed_response)
    assert_equal(7776000, @parsed_response['expires_in'], @parsed_response)
    assert(@parsed_response['refresh_token'], @parsed_response)
  end

  ##
  # AS-6206 | Authorization Code support for Cosmos
  #
  # Steps:
  # Setup
  # 1. Internal client requests client info for user client_id
  # 2. Internal client requests client info for internal client client_id
  def test_get_client_info_for_internal_tools
    # Setup
    @internal_tools = setup_user({ 'internal_tools' => true })
    @user = setup_user({'email' => @user.email})

    # Step 1
    headers = { 'Authorization' => "Bearer #{@internal_tools.oauth_token}" }

    params = { 'client_id' => @user.turtle_client_id }

    get '/client_info', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['name'], @parsed_response)
    assert_equal(params['client_id'], @parsed_response['client_id'], @parsed_response)
    assert(@parsed_response['redirect_uri'], @parsed_response)

    # Step 2
    params = { 'client_id' => @internal_tools.turtle_client_id }

    get '/client_info', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['name'], @parsed_response)
    assert_equal(params['client_id'], @parsed_response['client_id'], @parsed_response)
    assert(@parsed_response['redirect_uri'], @parsed_response)
  end

  ##
  # AS-6349 | Require zip code during user registration
  # AS-7254 | User model does not validate zip_code field properly
  #
  # Steps:
  # 1. Verify successful response for app_id WEB and 5 digit zip
  # 2. Verify successful response for app_id MOBWEB and 5-4 digit zip
  # 3. Verify successful response for app_id FOO and 5 digit zip
  # 4. Verify error response for app_id WEB/MOBWEB and missing zip codes
  # 5. Verify error response for app_id WEB/MOBWEB and invalid zip codes
  def test_new_account_requires_zip_for_web_mobweb_only
    @user = TurtleUser.new({ 'app_id' => 'WEB',
                             'zip_code' => '91203' })
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    turtle_response = @user.login
    assert_response(turtle_response, :success)

    @parsed_response = JSON.parse(turtle_response.body)
    assert_equal(@user.id, @parsed_response['id'], @parsed_response)
    assert_equal(@user.zip_code, @parsed_response['zip_code'], @parsed_response)

    # Step 2
    @user = TurtleUser.new({ 'app_id' => 'MOBWEB',
                             'zip_code' => '91203-1234 '})
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    turtle_response = @user.login
    assert_response(turtle_response, :success)

    @parsed_response = JSON.parse(turtle_response.body)
    assert_equal(@user.id, @parsed_response['id'], @parsed_response)
    assert_equal('91203-1234', @parsed_response['zip_code'], @parsed_response)

    # Step 3
    @user = TurtleUser.new({ 'app_id' => 'FOO',
                             'zip_code' => '91203' })
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    turtle_response = @user.login
    assert_response(turtle_response, :success)

    @parsed_response = JSON.parse(turtle_response.body)
    assert_equal(@user.id, @parsed_response['id'], @parsed_response)
    assert_equal(@user.zip_code, @parsed_response['zip_code'], @parsed_response)

    # Step 4
    @user = TurtleUser.new({ 'app_id' => ['WEB','MOBWEB'].sample })
    turtle_response = @user.register
    assert_response(turtle_response, :client_error)

    @parsed_response = JSON.parse(turtle_response.body)
    assert_equal('ValidationError', @parsed_response['error'])
    assert_equal("Zip code is not present.\nZip code is not valid.", @parsed_response['message'])

    # Step 5
    invalid_zip_codes = ['ABCDE','9120','912031','9120-1234','91203-123','91203-12345','912031-1234','91203-ABCD']

    invalid_zip_codes.each do |invalid_zip_code|
      @user = TurtleUser.new({ 'app_id' => ['WEB','MOBWEB'].sample,
                               'zip_code' => invalid_zip_code })
      turtle_response = @user.register
      assert_response(turtle_response, :client_error)

      @parsed_response = JSON.parse(turtle_response.body)
      assert_equal('ValidationError', @parsed_response['error'],
                   "Expected #{invalid_zip_code} to return the error: ValidationError")
      assert_equal('Zip code is not valid.', @parsed_response['message'],
                   "Expected #{invalid_zip_code} to return the error message: Zip code is not valid.")
    end
  end

  ##
  # AS-6914 | UGC: Parallel write the new user password
  #
  # Steps:
  # Setup
  # 1. Verify response for updating the users password
  def test_update_password_is_written_to_oracle_and_dragon
    # Setup
    @user = setup_user

    # Step 1
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    params = {
        'new_password' => 'new-password',
        'new_password_confirmation' => 'new-password',
        'old_password' => @user.password
    }

    put '/update_password', params, headers
    assert_response(@response, :success)
  end
end
