require './init'

class TestPandaEmail < APITest
  def setup
    assign_http(Config['panda']['host'])
    @user_params = { 'email_opt_in' => true }
    @user = setup_user(@user_params)
    @unverified_user = TurtleUser.new(@user_params)
    assert_response(@unverified_user.register, :success)
  end

  ##
  # AS-5750 | Test and Alerts for Tmail Templates
  # AS-7371 | YP4S: Email Actions
  # - POST '/em/share_coupon'
  #
  # Steps:
  # Setup: Configure user & coupon for test
  # 1. User shares a coupon with another user
  # 2. Verify response for a Non Registered User
  # 3. Verify response for an Unverified Registered User
  def test_share_coupon
    # setup
    @user2 = setup_user(@user_params)

    listings = get_listings_with_coupons_from_search
    listing = listings.sample
    int_xxid = listing['Int_Xxid']
    coupon_id = listing['Coupons'][0]['CouponId']

    # Step 1
    params = {
        'to' => @user2.email,
        'from' => @user.email,
        'from_name' => @user.first_name,
        'lid' => int_xxid,
        'cid' => coupon_id,
        'note' => 'Thought you might be interested in this deal!',
        'mobile' => false
    }

    post '/em/share_coupon', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    # Step 2
    params['to'] = Common.generate_email

    post '/em/share_coupon', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    # Step 3
    params['to'] = @unverified_user.email

    post '/em/share_coupon', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)
  end

  ##
  # AS-5750 | Test and Alerts for Tmail Templates
  # AS-7371 | YP4S: Email Actions
  # - POST '/em/share_listing'
  #
  # Steps:
  # Setup: Configure user & listing for test
  # 1. User shares a listing with another user
  # 2. Verify response for a Non Registered User
  # 3. Verify response for an Unverified Registered User
  def test_share_listing
    # setup
    @user2 = setup_user(@user_params)

    params =  {
        'vrid' => @user.vrid,
        'app_id' => 'WEB',
        'ptid' => 'API'
    }

    listings = []
    response = get_consumer_search_resp('pizza', 'los angeles, ca', params)
    response['SearchResult']['BusinessListings'].each do |listing|
      listings << listing['Int_Xxid']
    end

    # Step 1
    params = {
        'request_host' => 'http://www.xx.com',
        'to' => @user2.email,
        'from' => @user.email,
        'from_name' => @user.first_name,
        'lid' => listings.sample.to_s,
        'note' => 'Checkout this listing!',
        'mobile' => false
    }

    post '/em/share_listing', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    # Step 2
    params['to'] = Common.generate_email

    post '/em/share_listing', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    # Step 3
    params['to'] = @unverified_user.email

    post '/em/share_listing', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)
  end

  ##
  # AS-5750 | Test and Alerts for Tmail Templates
  # AS-7371 | YP4S: Email Actions
  # - POST '/em/share_mb_featured_collection'
  #
  # Steps:
  # Setup: Configure user & mb featured collection for test
  # 1. User shares a mb featured collection with another user
  # 2. Verify response for an Unverified Registered User
  def test_share_mb_featured_collection
    # setup
    @user2 = setup_user(@user_params)

    params = {
        'user_id' => @user.id,
        'page_id' => '123'
    }

    get '/mb/featured_collections', params
    assert_response(@response, :success)
    sub_type = @parsed_response['Collections'].map { |subtype| subtype['Subtype'] }
    assert(true, sub_type.all? { |x| x == 'FEATURED' })

    collections = @parsed_response['Collections']
    unique_collection = collections.sample
    ucid = unique_collection['UniqueCollectionId']

    # Step 1
    params = {
        'to' => @user2.email,
        'from' => @user.email,
        'from_name' => @user.first_name,
        'unique_collection_id' => ucid,
        'user_id' => @user.id,
        'mobile' => false
    }

    post '/em/share_mb', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    # Step 2
    params['to'] = @unverified_user.email

    post '/em/share_mb', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)
  end

  ##
  # AS-5750 | Test and Alerts for Tmail Templates
  # AS-7371 | YP4S: Email Actions
  # - POST '/em/share_mb_personal_collection'
  #
  # Steps:
  # Setup:
  # 1. Verify response sharing mb personal collection
  # 2. Verify response for an Unverified Registered User
  def test_share_mb_personal_collection
    # setup
    @user2 = setup_user(@user_params)

    params = {
        'oauth_token' => @user.oauth_token,
        'name' => 'Awesome Stuff'
    }

    post '/mb/collections', params
    assert_response(@response, :success)

    collection_code = @parsed_response['Collection']['Code']
    params.delete('name')

    get '/mb/collections', params
    assert_response(@response, :success)
    assert_includes(@parsed_response['Collections'].map { |c| c['Name'] }, 'Awesome Stuff')

    opts = { 'user_id' => @user.id }

    get_consumer_search_resp('restaurants', 'eagle rock, ca', opts)
    assert_response(@response, :success)

    int_xxid = @parsed_response['SearchResult']['BusinessListings'].first['Int_Xxid']

    params = {
        'oauth_token' => @user.oauth_token,
        'int_xxid' => int_xxid,
        'c' => collection_code
    }

    post '/mb/businesses', params
    assert_response(@response, :success)

    params['visibility'] = 'public'

    put "/mb/social/collections/#{collection_code}/scope", params
    assert_response(@response, :success)

    params = { 'oauth_token' => @user.oauth_token }

    get "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)
    assert_equal(int_xxid, @parsed_response['Businesses'].first['Int_Xxid'])

    collections = @parsed_response['Collection']
    ucid = collections['UniqueCollectionId']

    # Step 1
    params = {
        'to' => @user2.email,
        'from' => @user.email,
        'from_name' => @user.first_name,
        'unique_collection_id' => ucid,
        'user_id' => @user.id,
        'mobile' => false
    }

    post '/em/share_mb', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    # Step 2
    params['to'] = @unverified_user.email

    post '/em/share_mb', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)
  end

  ##
  # AS-5750 | Test and Alerts for Tmail Templates
  # AS-7371 | YP4S: Email Actions
  # - POST '/em/mb_tips/:id'
  #
  # setup: Configure user for test
  # Steps:
  # 1. Verify panda response for email endpoint
  def test_mb_tips
    # Step 1
    id = (rand(5) + 1)

    params = {
        'user_id' => @user.id
    }

    post "/em/mb_tips/#{id}", params
    assert_response(@response, :client_error)
  end

  ##
  # Test verification email is sent for new registered user
  #
  # Steps:
  # Setup: make certain the test email is a fresh account
  # 1. User registers does not verify account
  # 2. Verify both Panda & Turtle display the same unverified flag
  # 3. Verify panda response for email endpoint
  def test_verification_for_unverified_user
    # Step 1
    assert(@unverified_user.id)

    # Step 2
    lookup_user_by_email(@unverified_user.email)
    assert_equal(false, @parsed_response['verified'], @parsed_response)

    @unverified_user.login_oauth
    refute_nil(@unverified_user.oauth_token)

    get_user_info(@unverified_user.oauth_token)
    assert_equal(0, @parsed_response['verified'], @parsed_response)

    # Step 3
    assign_http(Config['panda']['host'])

    params = { 'user_id' => @unverified_user.id }

    post '/em/registration', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)
  end

  ##
  # AS-5750 | Test and Alerts for Tmail Templates
  # - POST '/em/verification_reminder'
  #
  # Steps:
  # Setup: make certain the test email is a fresh account
  # 1. Verify panda response for verification reminder endpoint
  # 2. Verify both Panda & Turtle display the same unverified flag
  # 3. Verify panda response for email endpoint
  def test_verification_reminder_for_unverified_user
    # Step 1
    assert(@unverified_user.id)

    # Step 2
    lookup_user_by_email(@unverified_user.email)
    assert_equal(false, @parsed_response['verified'], @parsed_response)

    @unverified_user.login_oauth
    refute_nil(@unverified_user.oauth_token)

    get_user_info(@unverified_user.oauth_token)
    assert_equal(0, @parsed_response['verified'], @parsed_response)
    
    # Step 3
    assign_http(Config['panda']['host'])

    params = {
        'user_id' => @unverified_user.id,
        'request_host' => 'http://www.xx.com',
    }

    post '/em/verification_reminder', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)
  end

  ##
  # AS-5750 | Test and Alerts for Tmail Templates
  # - POST '/em/welcome'
  #
  # Steps:
  # Setup: Configure user for test
  # 1. Verify panda response for email endpoint
  def test_welcome
    # Step 1
    params = {
        'request_host' => 'http://www.xx.com',
        'source' => 'WEB',
        'user_id' => @user.id
    }

    post '/em/welcome', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)
  end

  ##
  # AS-5750 | Test and Alerts for Tmail Templates
  # AS-7362 | Disable the 'YPS-Welcome-Back' email
  # - POST '/em/welcome_back'
  #
  # Steps:
  # 1. Verify panda response for email endpoint
  def test_welcome_back
    # Step 1
    params = {
        'request_host' => 'http://www.xx.com',
        'user_id' => @user.id
    }

    post '/em/welcome_back', params
    assert_response(@response, :client_error)
  end

  ##
  # AS-7320 | SEO: Brafton: Create an endpoint for e-mail Share of articles
  # AS-7371 | YP4S: Email Actions
  # - POST '/em/share_article'
  #
  # Steps:
  # Setup: Configure user & article for test
  # 1. User shares an article with another user
  # 2. Verify response for a Non Registered User
  # 3. Verify response for an Unverified Registered User
  def test_share_article
    # setup
    @user2 = setup_user(@user_params)

    get '/articles', {}
    assert_response(@response, :success)
    refute_empty(@parsed_response['Articles'])

    article_id = @parsed_response['Articles'].sample['Id']

    # Step 1
    params = {
        'request_host' => 'http://www.xx.com',
        'to' => @user2.email,
        'from' => @user.email,
        'from_name' => @user.first_name,
        'article_id' => article_id,
        'note' => 'Checkout this article!',
        'mobile' => false
    }

    post '/em/share_article', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    # Step 2
    params['to'] = Common.generate_email

    post '/em/share_article', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    # Step 3
    params['to'] = @unverified_user.email

    post '/em/share_article', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)
  end
end
