require './init'

class TestTurtleProfile < APITest

  def setup
    assign_http(Config['turtle']['host'])
    @user = TurtleUser.new
  end

  ##
  # AS-6386 | Support for new email subscription settings
  #
  # Steps:
  # Setup: Users, forward listing, confirm nonregistered user
  # 1. Verify response for updating email subscription settings, optout for nru
  # 2. Verify  updated email subscription settings
  def test_email_subscriptions_updates_for_nonregistered_users
    # Setup
    @user2 = setup_user

    listings = []
    response = get_consumer_search_resp
    response['SearchResult']['BusinessListings'].each do |listing|
      listings << listing['Int_Xxid']
    end

    assign_http(Config["panda"]["host"])

    params = {
        'request_host' => 'http://www.xx.com',
        'to' => @user.email,
        'from' => @user2.email,
        'from_name' => @user2.first_name,
        'lid' => listings.sample.to_s,
        'note' => 'Checkout this listing!',
        'mobile' => false
    }

    post '/em/share_listing', params
    assert_response(@response, :success)

    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    get_nonregisterd_user(@user.email)
    assert(@parsed_response['email_token'], @parsed_response)
    @user.email_token = @parsed_response['email_token']
    assert(@parsed_response['id'], @parsed_response)
    @user.id = @parsed_response['id'].to_i
    assert_equal(false, @parsed_response['consumer_optout'], @parsed_response) if @parsed_response['consumer_optout']
    assert_equal(false, @parsed_response['advertising_optout'], @parsed_response) if @parsed_response['advertising_optout']

    # Step 1
    assign_http(Config["turtle"]["host"])

    post "/optout/#{@user.email_token}", {}
    assert_response(@response, :redirect)

    get "/optout/#{@user.email_token}", {}
    assert_response(@response, :success)

    # Step 2
    get_nonregisterd_user(@user.email)
    assert_equal(true, @parsed_response['consumer_optout'], @parsed_response)
  end

  ##
  # AS-6386 | Support for new email subscription settings
  # AS-7483 | Turtle Email unsubscribe Page
  # AS-7522 | Add the email preferences to users/lookup endpoint
  #
  # Steps:
  # Setup: Users, forward listing
  # 1. Verify response for default email subscription settings on user from /usr/lookup & Dragon
  # 2. User joins a promo
  # 3. Verify email subscription settings update on user for promo options on user from /usr/lookup & Dragon
  # 4. Verify response for updated email subscription settings on user from /usr/lookup & Dragon for selected options
  # 5. Verify response for updated email subscription settings on user from /usr/lookup & Dragon for optout for user
  def test_email_subscriptions_updates_for_registered_users
    # Setup
    user_params = { 'email_opt_in' => true }

    @user1 = setup_user(user_params)
    @user2 = setup_user(user_params)

    opts =  {
        'vrid' => @user2.vrid,
        'app_id' => 'WEB',
        'ptid' => 'API'
    }

    get_consumer_search_resp('restaurants', 'new york, ny', opts)
    assert_response(@response, :success)

    refute_empty(@parsed_response['SearchResult']['BusinessListings'], @parsed_response['SearchResult'])
    listing = @parsed_response['SearchResult']['BusinessListings'].sample

    assign_http(Config['panda']['host'])

    params = {
        'request_host' => 'http://www.xx.com',
        'to' => @user1.email,
        'from' => @user2.email,
        'from_name' => @user2.first_name,
        'lid' => listing['ListingId'],
        'note' => 'Checkout this listing!',
        'mobile' => false
    }

    post '/em/share_listing', params
    assert_response(@response, :success)

    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)

    # Step 1
    get_dragon_email_subscriptions(@user1.id)
    assert_response(@response, :success)
    assert_equal(@user1.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(true, @parsed_response['feedback'], @parsed_response)
    assert_equal(true, @parsed_response['newsletters'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_bonus_offers'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_contributed_updates'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_helpful_votes'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_referral_program_updates'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_replies'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_weekly_updates'], @parsed_response)

    params = {
        'user_id' => @user1.id
    }

    get '/usr/lookup', params
    assert_response(@response, :success)
    email_subscriptions = @parsed_response['email_subscriptions']
    assert_equal(@user1.id, email_subscriptions['user_id'], email_subscriptions)
    assert_equal(true, email_subscriptions['feedback'], email_subscriptions)
    assert_equal(true, email_subscriptions['newsletters'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_bonus_offers'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_contributed_updates'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_helpful_votes'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_referral_program_updates'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_replies'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_weekly_updates'], email_subscriptions)

    # Step 2
    promo = get_promo_with_code('APIACTIVEPROMO')

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user1.oauth_token}" }

    params = {
        'promo_id' => promo['Id'],
        'promo_teams' => promo['TeamNames'].sample
    }

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 3
    get_dragon_email_subscriptions(@user1.id)
    assert_response(@response, :success)
    assert_equal(@user1.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(true, @parsed_response['feedback'], @parsed_response)
    assert_equal(true, @parsed_response['newsletters'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_bonus_offers'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_contributed_updates'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_helpful_votes'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_referral_program_updates'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_replies'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_weekly_updates'], @parsed_response)

    assign_http(Config['panda']['host'])

    params = {
        'user_id' => @user1.id
    }

    get '/usr/lookup', params
    assert_response(@response, :success)
    email_subscriptions = @parsed_response['email_subscriptions']
    assert_equal(@user1.id, email_subscriptions['user_id'], email_subscriptions)
    assert_equal(true, email_subscriptions['feedback'], email_subscriptions)
    assert_equal(true, email_subscriptions['newsletters'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_bonus_offers'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_contributed_updates'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_helpful_votes'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_referral_program_updates'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_replies'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_weekly_updates'], email_subscriptions)

    # Step 4
    assign_http(Config['turtle']['host'])

    params = {
        'pref' => {
            'feedback' => 0,
            'newsletters' => 0,
            'yp4s_bonus_offers' => 1,
            'yp4s_contributed_updates' => 1,
            'yp4s_helpful_votes' => 0,
            'yp4s_referral_program_updates' => 1,
            'yp4s_replies' => 0,
            'yp4s_weekly_updates' => 1,
        }
    }

    post "/optout/#{@user1.email_token}", params
    assert_response(@response, :redirect)

    get_dragon_email_subscriptions(@user1.id)
    assert_response(@response, :success)
    assert_equal(@user1.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(false, @parsed_response['feedback'], @parsed_response)
    assert_equal(false, @parsed_response['newsletters'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_bonus_offers'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_contributed_updates'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_helpful_votes'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_referral_program_updates'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_replies'], @parsed_response)
    assert_equal(true, @parsed_response['yp4s_weekly_updates'], @parsed_response)

    assign_http(Config['panda']['host'])

    params = {
        'user_id' => @user1.id
    }

    get '/usr/lookup', params
    assert_response(@response, :success)
    email_subscriptions = @parsed_response['email_subscriptions']
    assert_equal(@user1.id, email_subscriptions['user_id'], email_subscriptions)
    assert_equal(false, email_subscriptions['feedback'], email_subscriptions)
    assert_equal(false, email_subscriptions['newsletters'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_bonus_offers'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_contributed_updates'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_helpful_votes'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_referral_program_updates'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_replies'], email_subscriptions)
    assert_equal(true, email_subscriptions['yp4s_weekly_updates'], email_subscriptions)

    # Step 5
    assign_http(Config['turtle']['host'])

    params = {
        'pref' => {
            'unsubscribe_all' => 1
        }
    }

    post "/optout/#{@user1.email_token}", params
    assert_response(@response, :redirect)

    get_dragon_email_subscriptions(@user1.id)
    assert_response(@response, :success)
    assert_equal(@user1.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(false, @parsed_response['feedback'], @parsed_response)
    assert_equal(false, @parsed_response['newsletters'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_bonus_offers'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_contributed_updates'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_helpful_votes'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_referral_program_updates'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_replies'], @parsed_response)
    assert_equal(false, @parsed_response['yp4s_weekly_updates'], @parsed_response)

    assign_http(Config['panda']['host'])

    params = {
        'user_id' => @user1.id
    }

    get '/usr/lookup', params
    assert_response(@response, :success)
    email_subscriptions = @parsed_response['email_subscriptions']
    assert_equal(@user1.id, email_subscriptions['user_id'], email_subscriptions)
    assert_equal(false, email_subscriptions['feedback'], email_subscriptions)
    assert_equal(false, email_subscriptions['newsletters'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_bonus_offers'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_contributed_updates'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_helpful_votes'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_referral_program_updates'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_replies'], email_subscriptions)
    assert_equal(false, email_subscriptions['yp4s_weekly_updates'], email_subscriptions)
  end

  ##
  # AS-6932| Update avatar_sha1 from monkey when User uploads an avatar image
  #
  # Steps:
  # 1. User signs up.
  # 2. User uploads an avatar image to monkey with upload_and_link endpoint.
  # 3. Avatar_sha1 field in Turtle/Panda should be updated.
  def test_profile_image_upload_and_link_updates_avatar_sha1
    # Step 1
    @user = setup_user

    # Step 2
    image_response = upload_and_link_image_by_user_id(@user)
    parsed_response = JSON.parse(image_response.body)
    image_sha1 = parsed_response['id']

    # Step 3
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    get '/me', {}, headers
    assert_response(@response, :success)
    assert_match(image_sha1, @parsed_response['avatar_url'])
  end

  ##
  # AS-6989| Update avatar_sha1 in turtle from post 'b_image/:sha1' endpoint
  # if user is uploading a profile photo
  #
  # Steps:
  # 1. User signs up.
  # 2. User uploads an avatar image to monkey with link endpoint.
  # 3. Avatar_sha1 field in Turtle/Panda should be updated.
  def test_profile_image_link_updates_avatar_sha1
    # Step 1
    @user = setup_user

    # Step 2
    image_response = upload_and_link_image('user_id', @user.id, @user.oauth_token)
    image_sha1 = image_response

    # Step 3
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    get '/me', {}, headers
    assert_response(@response, :success)
    assert_match(image_sha1, @parsed_response['avatar_url'])
  end
end
