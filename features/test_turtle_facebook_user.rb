require './init'

class TestTurtleFacebookUser < APITest
  def setup
    @user = TurtleUser.new
    @fb_user = create_fb_user
  end

  def teardown
    assign_http(Config["facebook"]["host"])
    delete_test_user(@fb_user)
  end

  ##
  # STEPS:
  # 1. save something in mb as visitor
  # 2. OAuth login with Facebook VIA mobile path
  # 3. confirm UGC merge on my book
  def test_visitor_merge_through_facebook
    @user.email = @fb_user['email']
    # Step 1
    assign_http(Config["panda"]["host"])

    # convert to search
    params = {
        'type' => { 'shortcuts' => ['gas'] },
        'vrid' => @user.vrid
    }

    post '/mb/preferences', params
    assert_response(@response, :success)

    # Step 2
    params = {
        'vrid' => @user.vrid,
        'merge_history' => true
    }

    assign_http(Config["turtle"]["host"])

    get '/auth/facebook', params
    assert_response(@response, 302)
    assert_match(/https:\/\/www\.facebook\.com/, @response['location'])

    login_fb_user!(@fb_user, @user)

    # Step 3
    assign_http(Config["panda"]["host"])

    params = {
        'type' => 'shortcuts',
        'user_id' => @parsed_response['id']
    }

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Shortcuts'].size)
    assert_equal('gas', @parsed_response['Shortcuts'].first['Name'])
  end

  ##
  # STEPS:
  # 1. login on turtle using facebook account
  # 2. search for listing
  # 3. upload image to listing
  # 4. check image
  # 5. hide image
  def test_fb_sign_up_and_upload_monkey_image
    # Step 1
    @user.email = @fb_user['email']
    login_fb_user!(@fb_user, @user)

    # Step 2
    assign_http(Config["panda"]["host"])

    opts = { 'vrid' => @user.vrid }

    get_consumer_search_resp('ramen', 'glendale, ca', opts)
    assert_response(@response, :success)

    listing = @parsed_response['SearchResult']['BusinessListings'].first
    int_xxid = listing['Int_Xxid']

    # Step 3
    assign_http(Config["monkey"]["host"])

    headers = { 'Content-Type' => 'image/jpg' }

    params = {
        'api_key' => Config["monkey"]["api_key"],
        'oauth_token' => @user.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    put_file "/b_image", params, generate_random_image, headers
    assert_response(@response, :success)

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

    # Step 4
    assert_image_in_consumer_business(sha1, listing)
    assert_image_in_profile(sha1, @user)

    # Step 5
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

    params = { 'api_key' => Config["monkey"]["api_key"] }

    get "/business/images/#{int_xxid}", params
    assert_response(@response, :success)
    refute_empty(@parsed_response[int_xxid],
                 "Expected response for int_xxid #{int_xxid} to not be empty: #{@parsed_response}")
    refute(@parsed_response[int_xxid].map { |images| images['id'] }.include?(sha1),
           "Expected image removed from list after delete: #{sha1}")
  end

  ##
  # STEPS:
  # 1. sign up and login on turtle with same email as fb
  # 2. search for listing
  # 3. upload image to listing
  # 4. check image in profile, but not in mip
  # 5. login via fb of same email
  # 6. check image in mip and profile
  # 7. hide image
  def test_unverified_user_fb_sign_up_ugc_merge
    # Step 1
    @user.email = @fb_user['email']
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id)
    @user.login_oauth
    assert(@user.oauth_token)

    # Step 2
    assign_http(Config["panda"]["host"])

    opts = { 'vrid' => @user.vrid }

    get_consumer_search_resp('ramen', 'glendale, ca', opts)

    assert_response(@response, :success)

    listing = @parsed_response['SearchResult']['BusinessListings'].first
    int_xxid = listing['Int_Xxid']

    # Step 3
    assign_http(Config["monkey"]["host"])

    headers = { 'Content-Type' => 'image/jpg' }

    params = {
        'api_key' => Config["monkey"]["api_key"],
        'oauth_token' => @user.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    put_file "/b_image", params, generate_random_image, headers

    assert_response(@response, :success)
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

    # Step 4
    refute_image_in_consumer_business(sha1, listing)
    assert_image_in_profile(sha1, @user)

    # Step 5
    login_fb_user!(@fb_user, @user)

    # Step 6
    assert_image_in_consumer_business(sha1, listing)
    assert_image_in_profile(sha1, @user)

    # Step 7
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

    params = { 'api_key' => Config["monkey"]["api_key"] }

    get "/business/images/#{int_xxid}", params
    assert_response(@response, :success)
    refute_empty(@parsed_response[int_xxid],
                 "Expected response for int_xxid #{int_xxid} to not be empty: #{@parsed_response}")
    refute(@parsed_response[int_xxid].map { |images| images['id'] }.include?(sha1),
           "Expected image removed from list after delete: #{sha1}")
  end

  ##
  # STEPS:
  # 1. Login user though facebook
  # 2. Logout user (clear access token for sanity check)
  # 3. Sign up with same email should prompt password reset link
  # 4. Login with same email should prompt password reset link
  def test_user_fb_sign_up_web_login_register_password_prompt
    # Step 1
    @user.email = @fb_user['email']

    login_fb_user!(@fb_user, @user)

    # Step 2
    turtle_response = @user.logout
    assert_response(turtle_response, :redirect)

    # Step 3
    turtle_response = @user.register(true, false) # web view
    assert_response(turtle_response, 302)
    assert_match(/\/register/, turtle_response['location'])

    session = CGI::Cookie.parse(turtle_response['set-cookie'])['rack.session'].first
    refute_nil(session)

    headers = { 'Cookie' => "rack.session=#{CGI.escape(session)}" }

    assign_http(Config["turtle"]["host"])

    get '/register', {}, headers
    assert_response(@response, :success)
    assert_match(/new_password_confirmation/, @response.body)

    # Step 4
    turtle_response = @user.login(true, false) # web view
    assert_response(turtle_response, 302)
  end

  ##
  # AS-6487 | Facebook Account added to Dragon User
  #
  # Steps:
  # 1. Verify successful facebook authentication & login
  # 2. Confirm information for user form Dragon API
  # 3. User logs out, and confirm user from Dragon API
  # 4. Verify successful facebook authentication & login
  def test_fb_user_signup_then_login_logout_multiple_times
    @user.email = @fb_user['email']

    # Step 1
    params = {
        'vrid' => @user.vrid,
        'merge_history' => true
    }

    assign_http(Config["turtle"]["host"])

    get '/auth/facebook', params
    assert_response(@response, 302)
    assert_match(/https:\/\/www\.facebook\.com/, @response['location'])

    login_fb_user!(@fb_user, @user)
    assert(@user.oauth_token)

    lookup_user_by_id(@user.id)
    fb_uid = @parsed_response['facebook_uid']

    # Step 2
    get_user_info(@user.oauth_token)
    assert(@parsed_response['accounts'].length >= 1, @parsed_response)
    fb_account = @parsed_response['accounts'].first
    assert_equal('FacebookAccount', fb_account['type'], fb_account)
    assert(fb_account['identifier'], fb_account)

    get_dragon_user(@user.id)
    assert_response(@response, :success)

    assert(@parsed_response['facebook_uid'], @parsed_response)
    assert_equal(fb_uid, @parsed_response['facebook_uid'], @parsed_response)

    # Step 3
    turtle_response = @user.logout
    assert_response(turtle_response, :redirect)

    get_dragon_user(@user.id)
    assert_response(@response, :success)

    assert(@parsed_response['facebook_uid'], @parsed_response)
    assert_equal(fb_uid, @parsed_response['facebook_uid'], @parsed_response)

    # Step 4
    params = {
        'vrid' => @user.vrid,
        'merge_history' => true
    }

    assign_http(Config["turtle"]["host"])

    get '/auth/facebook', params
    assert_response(@response, 302)
    assert_match(/https:\/\/www\.facebook\.com/, @response['location'])

    login_fb_user!(@fb_user, @user)
    assert(@user.oauth_token)

    get_user_info(@user.oauth_token)
    assert(@parsed_response['accounts'].length >= 1, @parsed_response)
    fb_account = @parsed_response['accounts'].first
    assert_equal('FacebookAccount', fb_account['type'], fb_account)
    assert(fb_account['identifier'], fb_account)

    get_dragon_user(@user.id)
    assert_response(@response, :success)

    assert(@parsed_response['facebook_uid'], @parsed_response)
    assert_equal(fb_uid, @parsed_response['facebook_uid'], @parsed_response)
  end
end
