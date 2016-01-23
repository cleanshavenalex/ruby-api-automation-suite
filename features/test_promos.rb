require './init'

class TestPromos < APITest
  def setup
    @active_promo = 'APIACTIVEPROMO'
    @promo = get_promo_with_code(@active_promo)
    @active_promo_id = @promo['Id']
    @active_promo_points = get_promo_points(@active_promo_id)

    @expired_promo = 'APIEXPIREDPROMO'
    @not_started_promo = 'APINOTSTARTEDPROMO'
    @fake_promo = 'APIFAKEPROMO'

    assign_http(Config['snake']['host'])
    @api_key = Config['snake']['api_key']
  end

  def teardown
    delete_matching_promos
  end

  ##
  # AS-7086 | PTA - Use promo_id during user creation & fix web flow
  #
  # Steps
  # Setup
  # 1. Confirm account verified when creating new user with promo id
  # 2. Confirm account verified when updating new user with promo id
  # 3. Confirm account verified when creating new user with promo id via /oauth/authorize
  # 4. Confirm account not auto verified when creating new user with promo id
  def test_creating_updating_account_with_promo_id_auto_verifies
    assign_http(Config['turtle']['host'])

    params = { 'promo_id' => @active_promo_id }

    # Step 1
    @user = TurtleUser.new(params)
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert_equal(1, @user.verified)

    # Step 2
    @user = TurtleUser.new
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert_equal(0, @user.verified)

    turtle_response = @user.login_oauth
    assert_response(turtle_response, :success)

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['verified'])

    # Step 3
    params = { 'external_client' => true,
               'promo_id' => @active_promo_id }

    @user = TurtleUser.new(params)
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert(@user.id, turtle_response.body)
    turtle_response = @user.login_oauth_for_external_client('Allow')
    assert_response(turtle_response, :success)
    assert(@user.oauth_token)
    assert_equal(1, @user.verified)

    # Step 4
    params = { 'promo_id' => 9999999999999 }

    @user = TurtleUser.new(params)
    turtle_response = @user.register
    assert_response(turtle_response, :success)
    assert_equal(0, @user.verified)
  end

  ##
  # AS-7156 | Tools Changes - Update error response for already existing promo code
  #
  # Steps:
  # 1. Verify response for POST using existing promo code
  # 2. Verify response for case-sensitive POST using existing promo with downcased code | AS-7221
  def test_code_already_taken_response
    # Step 1
    assign_http(Config['panda']['host'])

    params = {
        'code' => @expired_promo,
        'start_date' => Time.now.to_i,
        'end_date' => (Time.now + 1.day).to_i
    }

    post '/pros', params
    assert_response(@response, :client_error)
    assert_equal('InvalidParamsError', @parsed_response['error'])
    assert_equal('code is already taken', @parsed_response['message'])

    # Step 2
    params['code'] = @not_started_promo.downcase

    post '/pros', params
    assert_response(@response, :client_error)
    assert_equal('InvalidParamsError', @parsed_response['error'])
    assert_equal('code is already taken', @parsed_response['message'])
  end

  ##
  # AS-6968 - Promo code validation
  # Promo exists and is active.
  def test_verify_code_success
    params = { 'code' => @active_promo }

    get '/pros/verify', params.merge(api_key)
    assert_response(@response, :success)
    assert_equal(@active_promo, @parsed_response['promo']['code'])
  end

  ##
  # AS-6968 - Promo code validation
  # Promo exists but current time is past the end date.
  def test_verify_code_expired
    expired_promo = get_promo_with_code(@expired_promo)
    assert(expired_promo['Id'])

    params = { 'code' => @expired_promo }

    get '/pros/verify', params.merge(api_key)
    assert_response(@response, :client_error)
    assert_equal('NotFoundError', @parsed_response['error'])
    assert_equal('Oops! That promo code isn\'t active.', @parsed_response['message'])
  end

  ##
  # AS-6968 - Promo code validation
  # Promo exists but current time is before the start date.
  def test_verify_code_not_started
    not_started_promo = get_promo_with_code(@not_started_promo)
    assert(not_started_promo['Id'])

    params = { 'code' => @not_started_promo }

    get '/pros/verify', params.merge(api_key)
    assert_response(@response, :client_error)
    assert_equal('NotFoundError', @parsed_response['error'])
    assert_equal('Oops! That promo code isn\'t active.', @parsed_response['message'])
  end

  ##
  # AS-6968 - Promo code validation
  # Promo does not exist
  def test_verify_code_nonexistant
    params = { 'code' => @fake_promo }

    get '/pros/verify', params.merge(api_key)
    assert_response(@response, :client_error)
    assert_equal('NotFoundError', @parsed_response['error'])
    assert_equal('Oops! That promo code isn\'t valid.', @parsed_response['message'])
  end

  ##
  # AS-6980 - Turtle POST /usr should verify new users if valid promo code is passed
  # AS-6970 - Turtle PUT /usr includes new user attributes
  # AS-6966 - Turtle GET /me endpoint returns promo object
  # AS-7049 - Increment user_count in promos table
  # AS-7241 | PTA- Server side validation for user attributes
  # AS-7305 | Add user_attributes to snake /snake/usr/profile response
  # AS-7381 | YP4S - Change user_attributes from hash to array
  #
  # Steps:
  # 1. Create a user with a valid promo code
  # 2. Check that the user is automatically verified
  # 3. Log in the user and get an oauth token
  # 4. Add new user attributes to the user, including a valid promo id
  # 5. Check that /me returns the new attributes and promo object, and user_count is correct for promo
  # 6. Check that /pros/dashboard returns the attributes in the correct format
  # 7. Check that /pros/user_attributes returns the unselected attributes in the correct format
  def test_auto_verify_and_promo_object_in_slash_me_with_valid_promo
    default_attributes_keys = @promo['DefaultAttributes'].split('|').map { |x| x.split(':').first }
    # Expects exact matching, first default attribute will be downcased
    default_attributes_keys.first.downcase!

    assign_http(Config['turtle']['host'])

    # Step 1
    user = TurtleUser.new('promo_id' => @active_promo_id)
    turtle_response = user.register
    assert_response(turtle_response, :success)

    # Step 2
    assert_equal(1, user.verified, 'User should be verified when registering with a valid promo code')

    # Step 3
    turtle_response = user.login
    assert_response(turtle_response, :success)
    user.login_oauth
    refute_nil(user.oauth_token, 'oauth_token is missing!')

    # Step 4
    headers = { 'Authorization' => "Bearer #{user.oauth_token}" }

    user_attributes = { 'not_default_key' => 'true' }
    default_attributes_keys.each do |key|
      user_attributes[key] = ['true','false'].sample
    end

    params = {
      'user' => {
        'user_attributes' => user_attributes
      },
      'promo_id' => @active_promo_id
    }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['user_attributes'], @parsed_response)
    assert_equal((user_attributes.length - 2), @parsed_response['user_attributes'].length, @parsed_response['user_attributes'])
    refute(@parsed_response['user_attributes'].find { |attributes| attributes['not_default_key'] },
           "Expected not to find not_default_key within the list of user attributes: #{@parsed_response['user_attributes']}")
    refute(@parsed_response['user_attributes'].find { |attributes| attributes[default_attributes_keys[0]] },
           "Expected not to find #{default_attributes_keys[0]} within the list of user attributes: #{@parsed_response['user_attributes']}")
    default_attributes_keys[1..3].each do |def_attr|
      assert(@parsed_response['user_attributes'].find { |attributes| attributes['attribute_name'] == def_attr },
             "Expected to find #{def_attr} within the list of user attributes: #{@parsed_response['user_attributes']}")
    end

    # Step 5
    params = { 'include_promos' => 'true' }

    get '/me', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['user_attributes'], @parsed_response)
    assert_equal((user_attributes.length - 2), @parsed_response['user_attributes'].length, @parsed_response['user_attributes'])
    refute(@parsed_response['user_attributes'].find { |attributes| attributes['not_default_key'] },
           "Expected not to find not_default_key within the list of user attributes: #{@parsed_response['user_attributes']}")
    refute(@parsed_response['user_attributes'].find { |attributes| attributes[default_attributes_keys[0]] },
           "Expected not to find #{default_attributes_keys[0]} within the list of user attributes: #{@parsed_response['user_attributes']}")
    default_attributes_keys[1..3].each do |def_attr|
      assert(@parsed_response['user_attributes'].find { |attributes| attributes['attribute_name'] == def_attr },
             "Expected to find #{def_attr} within the list of user attributes: #{@parsed_response['user_attributes']}")
    end

    assert(@parsed_response['promos'], @parsed_response)
    assert_equal(@active_promo_id, @parsed_response['promos'].first['id'], @parsed_response['promos'].first)
    assert_equal(@promo['UserCount'] + 1, @parsed_response['promos'].first['user_count'], @parsed_response['promos'].first)

    # Step 6
    assign_http(Config['snake']['host'])

    params = {
        'oauth_token' => user.oauth_token,
        'include_promos' => 'true',
        'include_user_attributes' => true
    }.merge(api_key)

    get '/snake/usr/profile', params
    assert_response(@response, :success)
    assert(@parsed_response['user'], @parsed_response)
    assert(@parsed_response['user']['user_attributes'], @parsed_response['User'])
    assert_equal((user_attributes.length - 2), @parsed_response['user']['user_attributes'].length, @parsed_response['user']['user_attributes'])
    refute(@parsed_response['user']['user_attributes'].find { |attributes| attributes['not_default_key'] },
           "Expected not to find not_default_key within the list of user attributes: #{@parsed_response['user']['user_attributes']}")
    refute(@parsed_response['user']['user_attributes'].find { |attributes| attributes[default_attributes_keys[0]] },
           "Expected not to find #{default_attributes_keys[0]} within the list of user attributes: #{@parsed_response['user']['user_attributes']}")
    default_attributes_keys[1..3].each do |def_attr|
      assert(@parsed_response['user']['user_attributes'].find { |attributes| attributes['attribute_name'] == def_attr },
             "Expected to find #{def_attr} within the list of user attributes: #{@parsed_response['user']['user_attributes']}")
    end

    assert(@parsed_response['promos'], @parsed_response)
    assert_equal(@active_promo_id, @parsed_response['promos'].first['id'], @parsed_response['promos'])
    assert_equal(@promo['UserCount'] + 1, @parsed_response['promos'].first['user_count'], @parsed_response['promos'].first)

    # Step 6
    params = {
        'access_token' => user.oauth_token,
        'user_in_promo' => true,
    }.merge(api_key)

    get '/pros/dashboard', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['promo_ratings'])
    @parsed_response['promo_ratings'].each do |rating|
      if rating['user'] && rating['user']['user_attributes']
        rating['user']['user_attributes'].each do |attributes|
          assert(attributes['attribute_name'], attributes)
          assert(attributes['attribute_state'], attributes)
        end
      end
    end

    # Step 7
    unselected_attribute = default_attributes_keys[0].capitalize

    params = {
        'access_token' => user.oauth_token,
        'promo_id' => @active_promo_id,
    }.merge(api_key)

    get '/pros/user_attributes', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['new_user_attributes'])
    assert_equal(unselected_attribute, @parsed_response['new_user_attributes'][0]['attribute_name'],
                 "Expected to find #{unselected_attribute} within the list of new user attributes: #{@parsed_response['new_user_attributes']}")
  end

  ##
  # AS-6980 - Turtle POST /usr should verify new users if valid promo code is passed
  # AS-6970 - Turtle PUT /usr includes new user attributes
  # AS-6966 - Turtle GET /me endpoint returns promo object
  #
  # Steps:
  # 1. Create a user with an invalid promo code
  # 2. Check that the user is NOT automatically verified
  # 3. Log in the user and get an oauth token
  # 4. Add new user attributes to the user, including an invalid promo id
  # 5. Check that /me does not return the new attributes and promo object
  def test_auto_verify_and_promo_object_in_slash_me_with_invalid_promo
    # Make sure we're using an invalid promo first to catch data issues before we assume it's a code issue.
    params = { 'code' => @expired_promo }

    get '/pros/verify', params.merge(api_key)
    assert_response(@response, :client_error, "Expected #{@expired_promo} to be an invalid, but it wasn't.")

    assign_http(Config['turtle']['host'])

    # Step 1
    user = TurtleUser.new('promo_id' => @expired_promo_id)
    turtle_response = user.register
    assert_response(turtle_response, :success)

    # Step 2
    assert_equal(0, user.verified, "User should not be verified when registering with an invalid promo code")

    # Step 3
    turtle_response = user.login
    assert_response(turtle_response, :success)
    user.login_oauth
    refute_nil(user.oauth_token, "oauth_token is missing!")

    # Step 4
    headers = { 'Authorization' => "Bearer #{user.oauth_token}" }

    user_attributes = {
      'human' => 'true',
      'spider' => 'false'
    }

    params = {
      'user' => {
        'user_attributes' => user_attributes
      },
      'promo_id' => 6245513451 # will never be a real promo id
    }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :client_error)

    # Step 5
    params = { 'include_promos' => 'true' }

    get '/me', params, headers
    assert_response(@response, :success)
    assert_empty(@parsed_response['user_attributes'])
    assert_empty(@parsed_response['promos'])
  end

  ##
  # AS-6972 - Points info for categories
  # AS-6973 - Display points on /cons/business
  # AS-6992 - Update the photo_count and contributed_points in promos_users when uploading an image for a promo
  # AS-7286 | Number of participants contributing in promo on school stats page
  #
  # Steps:
  # 1. Create a user and sign up for a promo
  # 2. Sign the user up for an active promo
  # 3. Get business associated with promo
  # 4. Get points for that business
  # 5. Check the user's dashboard and store the promo's contributed_points and photo_count for later.
  # 6. Check the user's dashboard and verify nothing was added to the promo or user_stats.
  # 7. Upload an image with the correct promo_id should succeed.
  # 8. Check the user's dashboard and see that the contributed_points and photo_count are correct.
  # 9. Check that the promo's contributed_points and photo_count are correct.
  # 10. Upload the same image to the business.
  # 11. Check the user's dashboard and see that the contributed_points and photo_count have not changed.
  # 12. Check that the promo's contributed_points and photo_count have not changed.
  def test_photo_upload_increases_contribution_and_photo_count_for_promo_user
    # Make sure we're using an active promo first to catch data issues before we assume it's a code issue.
    params = { 'code' => @active_promo }

    get '/pros/verify', params.merge(api_key)
    assert_response(@response, :success, "Expected #{@active_promo} to be a valid and active promo, but it wasn't.")
    promo = @parsed_response['promo']
    assert_equal(@active_promo, promo['code'])

    # Step 1
    user = TurtleUser.new('promo_id' => @expired_promo_id)
    turtle_response = user.register
    assert_response(turtle_response, :success)
    turtle_response = user.login
    assert_response(turtle_response, :success)
    user.login_oauth
    refute_nil(user.oauth_token, 'oauth_token is missing!')

    # Step 2
    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 3
    business_listings = get_promo_listings
    int_xxid = business_listings.sample['Int_Xxid']

    search_opts = { 'promo_id' => @active_promo_id }

    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)
    business = @parsed_response['Business']

    # Step 4
    business_points = get_promo_points_for_business(business['Int_Xxid'])
    photo_points = business_points['photo_points']

    # Step 5
    assign_http(Config['snake']['host'])

    params = {
      'access_token' => user.oauth_token,
      'promo_id' => @active_promo_id
    }

    get '/pros/dashboard', params.merge(api_key)
    assert_response(@response, :success)
    promo_photo_count = @parsed_response['promo']['photo_count']
    promo_contributed_points = @parsed_response['promo']['contributed_points']
    promo_user_count = @parsed_response['promo']['user_count']
    promo_contributing_user_count = @parsed_response['promo']['contributing_user_count']
    assert(promo_user_count >= promo_contributing_user_count,
           "Expected the User Count #{promo_user_count} to be greater than or equal to Contributing User Count #{promo_contributing_user_count}")

    # Step 6
    image_sha1 = upload_image(user.oauth_token)

    params = {
      'access_token' => user.oauth_token,
      'promo_id' => @active_promo_id
    }

    get '/pros/dashboard', params.merge(api_key)
    assert_response(@response, :success)
    assert_equal(0, @parsed_response['user_stats']['photo_count'])
    assert_equal(0, @parsed_response['user_stats']['contributed_points'])
    assert_equal(promo_photo_count, @parsed_response['promo']['photo_count'])
    assert_equal(promo_contributed_points, @parsed_response['promo']['contributed_points'])
    assert_equal(promo_contributing_user_count, @parsed_response['promo']['contributing_user_count'])

    # Step 7
    monkey_response = link_image(image_sha1, 'int_xxid', int_xxid, user.oauth_token, 'promo_id' => @active_promo_id)
    assert_response(monkey_response, :success)

    # Step 8
    params = {
      'access_token' => user.oauth_token,
      'promo_id' => @active_promo_id
    }

    get '/pros/dashboard', params.merge(api_key)
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['user_stats']['photo_count'])
    assert_equal(photo_points, @parsed_response['user_stats']['contributed_points'])
    assert_equal((promo_contributing_user_count + 1), @parsed_response['promo']['contributing_user_count'])

    # Step 9
    assert_equal((promo_photo_count + 1), @parsed_response['promo']['photo_count'])
    assert_equal((promo_contributed_points + photo_points), @parsed_response['promo']['contributed_points'])

    # Step 10
    monkey_response = link_image(image_sha1, 'int_xxid', int_xxid, user.oauth_token, 'promo_id' => @active_promo_id)
    assert_response(monkey_response, :success)

    # Step 11
    params = {
      'access_token' => user.oauth_token,
      'promo_id' => @active_promo_id
    }

    get '/pros/dashboard', params.merge(api_key)
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['user_stats']['photo_count'])
    assert_equal(photo_points, @parsed_response['user_stats']['contributed_points'])

    # Step 12
    assert_equal((promo_photo_count + 1), @parsed_response['promo']['photo_count'])
    assert_equal((promo_contributed_points + photo_points), @parsed_response['promo']['contributed_points'])
  end

  ##
  # AS-6972 - Points info for categories
  # AS-6973 - Display points on /cons/business
  # AS-6991 - Update the review_count and contributed_points in promos_users when uploading a review for a promo
  # AS-7027 - Update the review_count and contributed_points in promos when uploading a review for a promo
  # AS-7333 | YP4S - Wrap point calculations in one transaction
  # AS-7358 | YP4S - Ceil points after applying multiplier
  #
  # Steps:
  # 1. Create a user and sign up for a promo
  # 2. Get business and review points associated with promo
  # 3. Check the user's base dashboard
  # 4. Review the business with a valid promo
  # 5. Check the user's dashboard updates correct contributed points and review count
  # 6. Add user to two teams
  # 7. Get a new int_xxid for review and calculate ceiling points
  # 8. Add second review for user
  # 9. Check user's dasboard is correct with new calculated ceiling points
  def test_reviewing_increases_contribution_and_review_count_for_promo_user
    # Setup
    @user = setup_user

    # Step 1
    assign_http(Config['turtle']['host'])

    my_teams = @promo['TeamNames'].pop(2)

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = {
        'promo_id' => @active_promo_id,
        'promo_team' => "#{my_teams[0]}"
    }

    put '/usr', params, headers
    assert_response(@response, :success)
    assert_equal(params['promo_team'], @parsed_response['promo_team'], @parsed_response['promo_team'])
    assert(my_teams.include?(@parsed_response['promo_teams'][0]), @parsed_response['promo_teams'])

    # Step 2
    business_listings = get_promo_listings.shuffle
    int_xxid = business_listings.first['Int_Xxid']

    search_opts = { 'promo_id' => @active_promo_id }

    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)
    review_points = get_promo_points_for_business(@parsed_response['Business']['Int_Xxid'])['review_points']

    # Step 3
    assign_http(Config['snake']['host'])

    params = {
      'access_token' => @user.oauth_token,
      'promo_id' => @active_promo_id
    }.merge(api_key)

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(0, @parsed_response['user_stats']['review_count'])
    assert_equal(0, @parsed_response['user_stats']['contributed_points'])
    assert_equal(@promo['ReviewCount'] , @parsed_response['promo']['review_count'])
    assert_equal(@promo['ContributedPoints'], @parsed_response['promo']['contributed_points'])
    promo_review_count = @parsed_response['promo']['review_count']
    promo_contributed_points = @parsed_response['promo']['contributed_points']

    # Step 4
    params = {
      'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
      'source' => 'XX3',
      'subject' => 'Review made by API',
      'value' => rand(1..5),
      'listing_id' => int_xxid,
      'oauth_token' => @user.oauth_token,
      'promo_id' => @active_promo_id
    }.merge(api_key)

    put '/snake/usr/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['ratings'], @parsed_response)
    assert(@parsed_response['ratings']['Rating'], @parsed_response['ratings'])
    assert_equal(review_points, @parsed_response['ratings']['Rating']['Points'],
                 "Expected business promo points #{review_points} to match response: #{@parsed_response['ratings']['Rating']['Points']}")

    # Step 5
    params = {
      'access_token' => @user.oauth_token,
      'promo_id' => @active_promo_id
    }.merge(api_key)

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['user_stats']['review_count'])
    assert_equal(review_points, @parsed_response['user_stats']['contributed_points'])
    assert_equal(promo_review_count + 1, @parsed_response['promo']['review_count'])
    assert_equal(promo_contributed_points + review_points, @parsed_response['promo']['contributed_points'])

    # Step 6
    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = {
        'promo_id' => @active_promo_id,
        'promo_teams' => my_teams
    }

    put '/usr', params, headers
    assert_response(@response, :success)
    assert(my_teams.include?(@parsed_response['promo_team']), @parsed_response['promo_team'])
    assert_equal(my_teams.sort, @parsed_response['promo_teams'].sort, @parsed_response['promo_teams'])

    # Step 7
    int_xxid = business_listings[1]['Int_Xxid']

    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)
    review_points_2 = get_promo_points_for_business(@parsed_response['Business']['Int_Xxid'])['review_points']
    split_total_points = ((review_points_2.to_f / my_teams.length).ceil * my_teams.length)

    # Step 8
    assign_http(Config['snake']['host'])

    params = {
        'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
        'source' => 'XX3',
        'subject' => 'Review made by API',
        'value' => rand(1..5),
        'listing_id' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'promo_id' => @active_promo_id
    }.merge(api_key)

    put '/snake/usr/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['ratings'], @parsed_response)
    assert(@parsed_response['ratings']['Rating'], @parsed_response['ratings'])
    assert_equal(split_total_points, @parsed_response['ratings']['Rating']['Points'],
                 "Expected business promo points #{split_total_points} to match response: #{@parsed_response['ratings']['Rating']['Points']}")

    # Step 9
    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id
    }.merge(api_key)

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(2, @parsed_response['user_stats']['review_count'])
    assert_equal((split_total_points + review_points), @parsed_response['user_stats']['contributed_points'])
  end

  ##
  # AS-6975 | PTA - create a new endpoint GET /pros/leaderboard for the PTA leaderboard
  # AS-7078 | PTA - Leaderboard/Dashboard should support stats by team type
  # AS-7231 | PTA - Leaderboard calls need to be integrated & support individual leaderboards
  # AS-7243 | YP4S - Ability to switch between multiple teams for a promo
  # AS-7303 | YP4S Tools support - Leaderboard for tools
  #
  # Steps:
  # Setup
  # 1. Get leaderboard information from lookup
  # 2. Get initial leaderboard and promo information via snake
  # 3. Get business for promo
  # 4. get points for business
  # 5. Add review and photo for promo
  # 6. Verify stat changes within leaderboard for user, team, and promo
  # 7. Verify response with h & h_user added for limiting leaderboard and top users
  def test_promos_leaderboard
    # Setup
    @user = setup_user

    assign_http(Config['panda']['host'])

    lookup_params = { 'promo_id' => @active_promo_id }

    get '/pros/lookup', lookup_params
    assert_response(@response, :success)
    assert_equal(@active_promo, @parsed_response['Promo']['Code'])
    refute(@parsed_response['TeamLeaderboard'], @parsed_response)
    refute_empty(@parsed_response['Promo']['TeamNames'], @parsed_response['Promo'])
    teams = @parsed_response['Promo']['TeamNames'].shuffle
    my_team = teams[0]

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    user_params = {
        'promo_id' => @active_promo_id,
        'my_teams' => my_team
    }

    user_params['promo_team'] = my_team

    put '/usr', user_params, headers
    assert_response(@response, :success)
    assert_equal(my_team, @parsed_response['promo_team'], @parsed_response['promo_team'])
    assert(@parsed_response['promo_teams'].include?(my_team), @parsed_response['promo_teams'])

    # Step 1
    assign_http(Config['panda']['host'])

    lookup_params['include_team_leaderboard'] = true

    get '/pros/lookup', lookup_params
    assert_response(@response, :success)
    assert_equal(@active_promo, @parsed_response['Promo']['Code'])
    assert(@parsed_response['TeamLeaderboard'], @parsed_response)
    refute_empty(@parsed_response['TeamLeaderboard'])
    assert(@parsed_response['TeamLeaderboard'].find { |team| team['Name'] == my_team },
           "Expected #{my_team} to be listed within the TeamLeaderboard for lookup: #{@parsed_response['TeamLeaderboard']}")

    # Step 2
    assign_http(Config['snake']['host'])

    promo_params = {
        'promo_id' => @active_promo_id,
        'access_token' => @user.oauth_token,
    }.merge(api_key)

    get '/pros/leaderboard', promo_params
    assert_response(@response, :success)
    promo = @parsed_response['promo']
    assert_equal(@active_promo_id , promo['id'], promo)
    refute_empty(promo['team_names'], promo)
    leaderboard = @parsed_response['leaderboard']
    leaderboard.each do |team|
      leaderboard.delete(team) if team == 'red' || team == 'blue' # old teams still in promo, no longer used
    end
    team_status = leaderboard.find { |team| team['name'] == my_team }
    assert(team_status, "Expected team #{my_team} to be listed within the team leaderboard list: #{team_status}")
    initial_team_contributed_points = team_status['contributed_points']

    top_users = @parsed_response['top_users']
    assert_equal((10 + 1), top_users.length)
    user_status = top_users.find { |user| user['user_id'] == @user.id }
    assert(user_status, "Expected user id #{@user.id} to be listed within the top_users list: #{top_users}")
    assert_equal(0, user_status['contributed_points'], user_status)

    # Step 3
    business_listings = get_promo_listings
    int_xxid = business_listings.sample['Int_Xxid']

    # Step 4
    search_opts = { 'promo_id' => @active_promo_id }

    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)
    assert(@parsed_response['Business'], @parsed_response)
    promo_points = get_promo_points_for_business(@parsed_response['Business']['Int_Xxid'])
    total_points = (promo_points['review_points'] + promo_points['photo_points'])

    # Step 5
    params = {
        'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
        'source' => 'XX3',
        'subject' => 'Review made by API',
        'value' => rand(1..5),
        'listing_id' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
    }.merge(api_key)

    put '/snake/usr/reviews', params
    assert_response(@response, :success)

    # 4.18.1 -- User submits multiple photo same int_xxid and promo, no additional points should be awarded | AS-7171
    2.times do
      upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid, @user, @active_promo_id)
      assert_response(@response, :success)
    end

    # Step 6
    get '/pros/leaderboard', promo_params
    assert_response(@response, :success)
    leaderboard = @parsed_response['leaderboard']
    leaderboard.each do |team|
      leaderboard.delete(team) if team == 'red' || team == 'blue' # old teams still in promo, no longer used
    end
    updated_team_status = leaderboard.find { |team| team['name'] == my_team }
    assert(updated_team_status, "Expected team #{my_team} to be listed within the team leaderboard list: #{team_status}")

    top_users = @parsed_response['top_users']
    assert_equal((10 + 1), top_users.length)
    updated_user_status = top_users.find { |user| user['user_id'] == @user.id }
    assert(updated_user_status, "Expected user id #{@user.id} to be listed within the top_users list: #{top_users}")

    # Check User Stats
    assert_equal(total_points, updated_user_status['contributed_points'],
                 "Expected Updated User Stats Contributed Points: #{updated_user_status['contributed_points']}, to match Total Points for Review and 1x Photo: #{total_points}")
    # Check Team Stats
    assert_equal((initial_team_contributed_points + total_points), updated_team_status['contributed_points'],
                 "Expected Updated Team Stats Contributed Points: #{updated_team_status['contributed_points']}, to match Initial Contributed Points + Total Points for Review and 1x Photo: #{(initial_team_contributed_points + total_points)}")

    # Step 7
    leaderboard_limit = 1
    top_users_limit = rand(1..9)

    promo_params['h'] = leaderboard_limit
    promo_params['h_users'] = top_users_limit

    get '/pros/leaderboard', promo_params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['promo']['enable_user_leaderboard'])
    assert_equal((top_users_limit + 1), @parsed_response['top_users'].length)
    if @parsed_response['leaderboard'][0]['name'] == my_team
      assert_equal(leaderboard_limit, @parsed_response['leaderboard'].length)
    else
      assert_equal((leaderboard_limit + 1), @parsed_response['leaderboard'].length)
    end
  end

  ##
  # PTA: Points bonus for first photo or review | AS-7029
  #
  # Steps:
  # Setup
  # 1. Get bonus first and base points data
  # 2. Get dashboard for user to confirm starting data for new users
  # 3. Add reviews and photos for new users
  # 4. Verify consumer business promo data update after first review
  # 5. Verify updates stats for new users
  # 6. Verify the Dashboard displays the accumulative totals
  def test_promo_points_bonus_first_photo_review
    # Setup
    params = {
        'code' => @active_promo,
        'api_key' => @api_key
    }

    get '/pros/verify', params
    assert_response(@response, :success, "Expected #{@active_promo} to be a valid and active promo, but it wasn't.")
    assert_equal(@active_promo, @parsed_response['promo']['code'])
    assert(@parsed_response['promo']['first_photo_bonus_points'] > 0)
    assert(@parsed_response['promo']['first_review_bonus_points'] > 0)

    @user1 = setup_user({ 'promo_id' => @active_promo_id })

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user1.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    @user2 = setup_user({ 'promo_id' => @active_promo_id })

    headers['Authorization'] = "Bearer #{@user2.oauth_token}"
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    int_xxid = 476303692

    search_opts = { 'promo_id' => @active_promo_id }

    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)
    assert(@parsed_response['Business']['Rateable'] == 1, "The Int_Xxid #{int_xxid} is not Rateable: #{@parsed_response}")
    business = @parsed_response['Business']

    unless business['Ratings'].empty?
      assign_http(Config['panda']['host'])

      business['Ratings'].each do |rating|
        delete "/rats/#{rating['Id']}", {}
        assert_response(@response, :success)
      end

      get_consumer_business_resp(int_xxid, search_opts)
      assert_response(@response, :success)
      business = @parsed_response['Business']
      assert_empty(business['Ratings'])
    end

    unless business['Media']['Data'].empty?
      assign_http(Config['monkey']['host'])

      business['Media']['Data'].each do |media|
        if media['ImagePath']
          params = { 'api_key' => Config['monkey']['api_key'] }
          delete media['ImagePath'], params
          assert_response(@response, :success)
        end
      end

      get_consumer_business_resp(int_xxid, search_opts)
      assert_response(@response, :success)
      business = @parsed_response['Business']
      assert_empty(business['Media']['Data'])
    end

    assert(business['Promo'], business)
    bonus_first_photo_points = business['Promo']['PhotoPoints']
    bonus_first_review_points = business['Promo']['ReviewPoints']
    bonus_first_total_points = (bonus_first_photo_points + bonus_first_review_points)

    base_promo_stats = get_promo_with_code(@active_promo)

    # Step 1
    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)
    business = @parsed_response['Business']

    business_points = get_promo_points_for_business(business['Int_Xxid'])
    base_photo_points = business_points['photo_points']
    base_review_points = business_points['review_points']
    base_total_points = (base_review_points + base_photo_points)
    assert_equal(base_photo_points, bonus_first_photo_points,
                 'Expected base_photo_points to equal bonus_first_photo_points')
    assert_equal(base_review_points, bonus_first_review_points,
                 'Expected base_review_points to equal bonus_first_review_points')
    assert_equal(base_total_points, bonus_first_total_points,
                 'Expected base_total_points to equal bonus_first_total_points')

    # Step 2
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user1.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    user1_base_stats = @parsed_response['user_stats']
    assert_equal(0, user1_base_stats['photo_count'], user1_base_stats)
    assert_equal(0, user1_base_stats['review_count'], user1_base_stats)
    assert_equal(0, user1_base_stats['contributed_points'], user1_base_stats)

    params['access_token'] = @user2.oauth_token

    get '/pros/dashboard', params
    assert_response(@response, :success)
    user2_base_stats = @parsed_response['user_stats']
    assert_equal(0, user2_base_stats['photo_count'], user2_base_stats)
    assert_equal(0, user2_base_stats['review_count'], user2_base_stats)
    assert_equal(0, user2_base_stats['contributed_points'], user2_base_stats)

    assert_equal(base_promo_stats['ReviewCount'], @parsed_response['promo']['review_count'],
                 "Expected review_count #{@parsed_response['promo']['review_count']} to equal: #{base_promo_stats['ReviewCount']}")
    assert_equal(base_promo_stats['PhotoCount'], @parsed_response['promo']['photo_count'],
                 "Expected photo_count #{@parsed_response['promo']['photo_count']} to equal: #{base_promo_stats['PhotoCount']}")
    assert_equal(base_promo_stats['ContributedPoints'], @parsed_response['promo']['contributed_points'],
                 "Expected dashboard contributed_points #{@parsed_response['promo']['contributed_points']} to equal promo verify base contributed points: #{base_promo_stats['ContributedPoints']}")

    # Step 3
    review_params = {
        'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
        'source' => 'XX3',
        'subject' => 'Review made by API',
        'value' => rand(1..5),
        'listing_id' => int_xxid,
        'oauth_token' => @user1.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    put '/snake/usr/reviews', review_params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['ratings']['Rating']['PromoId'])
    assert_equal(bonus_first_review_points, @parsed_response['ratings']['Rating']['Points'])

    upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid, @user1, @active_promo_id)
    assert_response(@response, :success)

    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)
    business = @parsed_response['Business']

    business_points = get_promo_points_for_business(business['Int_Xxid'])
    updated_review_points = business_points['review_points']
    updated_photo_points = business_points['photo_points']
    updated_total_points = (updated_review_points + updated_photo_points)
    assert((base_photo_points > updated_photo_points),
                 "Expected updated_photo_points #{updated_photo_points}, to be less than base_photo_points: #{base_photo_points}")
    assert((base_review_points > updated_review_points),
                 "Expected updated_review_points: #{updated_review_points}, to be less than base_review_points: #{base_review_points}")

    assign_http(Config['snake']['host'])

    review_params['oauth_token'] = @user2.oauth_token

    put '/snake/usr/reviews', review_params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['ratings']['Rating']['PromoId'])
    assert_equal(updated_review_points, @parsed_response['ratings']['Rating']['Points'])

    upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid, @user2, @active_promo_id)
    assert_response(@response, :success)

    # Step 4
    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)
    assert_equal(updated_photo_points, @parsed_response['Business']['Promo']['PhotoPoints'], @parsed_response)
    assert_equal(updated_review_points, @parsed_response['Business']['Promo']['ReviewPoints'], @parsed_response)
    assert_equal(updated_total_points, @parsed_response['Business']['Promo']['TotalPoints'], @parsed_response)

    # Step 5
    params = {
        'access_token' => @user1.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    user1_updated_stats = @parsed_response['user_stats']
    assert_equal(1, user1_updated_stats['photo_count'], user1_updated_stats)
    assert_equal(1, user1_updated_stats['review_count'], user1_updated_stats)
    assert_equal(base_total_points, user1_updated_stats['contributed_points'], user1_updated_stats)

    params['access_token'] = @user2.oauth_token

    get '/pros/dashboard', params
    assert_response(@response, :success)
    user2_updated_stats = @parsed_response['user_stats']
    assert_equal(1, user2_updated_stats['photo_count'], user2_updated_stats)
    assert_equal(1, user2_updated_stats['review_count'], user2_updated_stats)
    assert_equal(updated_total_points, user2_updated_stats['contributed_points'], user2_updated_stats)

    # Step 6
    contributed_points = (base_promo_stats['ContributedPoints'] + base_total_points + updated_total_points)
    assert_equal((base_promo_stats['ReviewCount'] + 2), @parsed_response['promo']['review_count'],
                 "Expected review_count #{@parsed_response['promo']['review_count']} to equal: #{(base_promo_stats['ReviewCount'] + 2)}")
    assert_equal((base_promo_stats['PhotoCount'] + 2), @parsed_response['promo']['photo_count'],
                 "Expected photo_count #{@parsed_response['promo']['photo_count']} to equal: #{(base_promo_stats['PhotoCount'] + 2)}")
    assert_equal(contributed_points, @parsed_response['promo']['contributed_points'],
                 "Expected dashboard contributed_points #{@parsed_response['promo']['contributed_points']} to equal promo verify base contributed points + added points: #{contributed_points}")
  end

  ##
  # AS-7211 | must have valid team name if promo has team names
  # AS-7280 | YP4S - Send Promo Team in me.json response
  # AS-7243 | YP4S - Ability to switch between multiple teams for a promo
  # AS-7173 | YP4S - Maintain active promos for a user (dashboard / leaderboard)
  # AS-7408 | YP4S - First promo in /me should be active promo
  #
  # Steps:
  # Setup: Create Promo & User
  # 1. Verify response for user with an invalid promo team
  # 2. Verify dashboard response for user with a valid promo team using promo_id param
  # 4. Verify dashboard error response for user with a valid promo team using only oauth_token
  # 4. Verify dashboard response for user with a valid promo team using user_in_promo param
  # 5. Verify response for user /me displays the promo team
  # 6. Verify response for user with a new team
  # 7. Verify response for user with a new team using user_in_promo param
  # 8. Verify response for user /me displays the new promo team
  # 9. Verify response for same user with a valid new promo team
  # 10. Verify response for user /me displays the both promo teams
  # 11. Verify leaderboard response for user for both promos team using promo_id param
  # 12. Verify leaderboard response for user for active promo team using user_in_promo param
  def test_user_with_multiple_promo_teams
    # Setup
    @user = setup_user
    @user2 = setup_user

    promo_params = { 'start_date' => (Time.now - 1.day).to_i }

    create_new_promo(promo_params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo']['Id'])
    refute_empty(@parsed_response['Promo']['TeamNames'])
    promo = @parsed_response['Promo']
    team_names = promo['TeamNames'].shuffle!
    my_teams = team_names.pop(2)

    create_new_promo(promo_params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo']['Id'])
    refute_empty(@parsed_response['Promo']['TeamNames'])
    promo_2 = @parsed_response['Promo']
    team_names_2 = promo_2['TeamNames'].shuffle!
    my_teams_2 = team_names_2.pop(2)

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    # Step 1
    assign_http(Config['turtle']['host'])

    user_params = {
        'promo_id' => promo['Id'],
        'promo_team' => 'NOT_A_VALID_TEAM',
    }

    put '/usr', user_params, headers
    assert_response(@response, :client_error)
    assert_equal('InvalidParamsError', @parsed_response['error'])
    assert_equal("#{user_params['promo_team']} are not valid teams", @parsed_response['message'])

    # Step 2
    user_params_2 = {
        'promo_id' => promo_2['Id'],
        'promo_team' => my_teams_2[0],
    }

    put '/usr', user_params_2, headers
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    assert_equal(@parsed_response['active_promo_id'], @parsed_response['promo']['id'])
    assert_equal(my_teams_2[0], @parsed_response['promo_team'],
           "Expected for team #{my_teams_2[0]} to be listed within promo_team: #{@parsed_response['promo_team']}")
    assert(@parsed_response['promo_teams'].include?(my_teams_2[0]),
           "Expected for team #{my_teams_2[0]} to be listed within promo_teams: #{@parsed_response['promo_teams']}")

    user_params['promo_team'] = my_teams[0]

    put '/usr', user_params, headers
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    assert_equal(@parsed_response['active_promo_id'], @parsed_response['promo']['id'])
    assert_equal(my_teams[0], @parsed_response['promo_team'],
                 "Expected for team #{my_teams[0]} to be listed within promo_team: #{@parsed_response['promo_team']}")
    assert(@parsed_response['promo_teams'].include?(my_teams[0]),
           "Expected for team #{my_teams[0]} to be listed within promo_teams: #{@parsed_response['promo_teams']}")

    assign_http(Config['snake']['host'])

    params = {
      'access_token' => @user.oauth_token,
      'promo_id' => promo['Id'],
    }.merge(api_key)

    get '/pros/dashboard', params, headers
    assert_response(@response, :success)
    dashboard = @parsed_response
    assert_equal(promo['Id'].to_s, @parsed_response['original_request']['promo_id'])
    assert(dashboard['user_stats'])
    assert(my_teams.include?(dashboard['user_stats']['team_name']), dashboard['user_stats']['team_name'])
    assert(dashboard['user_stats']['team_names'].include?(my_teams[0]), dashboard['user_stats']['promo_teams'])

    # Step 3
    params = {
        'access_token' => @user2.oauth_token,
    }.merge(api_key)

    get '/pros/dashboard', params, headers
    assert_response(@response, :client_error)
    assert_equal('MissingRequiredParamsError', @parsed_response['error'])
    assert_equal('promo_id must be specified (no active promo)', @parsed_response['message'])

    # Step 4
    params = {
        'access_token' => @user.oauth_token,
        'user_in_promo' => true,
    }.merge(api_key)

    get '/pros/dashboard', params, headers
    assert_response(@response, :success)
    assert_equal('true', @parsed_response['original_request']['user_in_promo'])
    assert(@parsed_response['user_stats'])
    assert_equal(dashboard['user_stats'], @parsed_response['user_stats'], 'Expected Dashboard response to match using promo_id or user_in_promo parameters')

    # Step 5
    get_user_info(@user.oauth_token, { 'include_promos' => true })
    assert_response(@response, :success)
    refute_empty(@parsed_response['promos'], @parsed_response)
    assert_equal(@parsed_response['active_promo_id'], @parsed_response['promos'][0]['id'])
    profile_promo = @parsed_response['promos'].find { |p| p['id'] == promo['Id'] }
    assert(profile_promo['team_names'].include?(my_teams[0]), @parsed_response['promos'])
    refute_empty(@parsed_response['promo_teams']["#{promo['Id']}"])
    assert(@parsed_response['promo_teams']["#{promo['Id']}"].include?(my_teams[0]))
    refute_empty(@parsed_response['promo_teams']["#{promo_2['Id']}"])
    assert(@parsed_response['promo_teams']["#{promo_2['Id']}"].include?(my_teams_2[0]))
    refute(@parsed_response['promo_teams']["#{promo_2['Id']}"].include?(my_teams_2[1]))

    # Step 6
    assign_http(Config['turtle']['host'])

    user_params.delete('promo_team')
    user_params['promo_teams'] = my_teams

    put '/usr', user_params, headers
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    assert_equal(@parsed_response['active_promo_id'], @parsed_response['promo']['id'])
    assert(my_teams.include?(@parsed_response['promo_team']), @parsed_response['promo_team'])
    assert(@parsed_response['promo_teams'].include?(my_teams[0]), @parsed_response['promo_teams'])
    assert(@parsed_response['promo_teams'].include?(my_teams[1]), @parsed_response['promo_teams'])

    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => promo['Id'],
    }.merge(api_key)

    get '/pros/dashboard', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['user_stats'])
    assert(my_teams.include?(@parsed_response['user_stats']['team_name']), @parsed_response['user_stats']['team_name'])
    assert(@parsed_response['user_stats']['team_names'].include?(my_teams[0]), @parsed_response['promo_teams'])
    assert(@parsed_response['user_stats']['team_names'].include?(my_teams[1]), @parsed_response['promo_teams'])

    # Step 7
    params = {
        'access_token' => @user.oauth_token,
        'user_in_promo' => true,
    }.merge(api_key)

    get '/pros/dashboard', params, headers
    assert_response(@response, :success)
    assert_equal('true', @parsed_response['original_request']['user_in_promo'])
    assert(@parsed_response['user_stats'])
    assert(my_teams.include?(@parsed_response['user_stats']['team_name']), @parsed_response['user_stats']['team_name'])
    assert(@parsed_response['user_stats']['team_names'].include?(my_teams[0]), @parsed_response['promo_teams'])
    assert(@parsed_response['user_stats']['team_names'].include?(my_teams[1]), @parsed_response['promo_teams'])

    # Step 8
    get_user_info(@user.oauth_token, { 'include_promos' => true })
    assert_response(@response, :success)
    refute_empty(@parsed_response['promos'], @parsed_response)
    assert_equal(@parsed_response['active_promo_id'], @parsed_response['promos'][0]['id'])
    profile_promo = @parsed_response['promos'].find { |p| p['id'] == promo['Id'] }
    assert(profile_promo['team_names'].include?(my_teams[0]), @parsed_response['promos'])
    assert(profile_promo['team_names'].include?(my_teams[1]), @parsed_response['promos'])
    refute_empty(@parsed_response['promo_teams']["#{promo['Id']}"])
    assert(@parsed_response['promo_teams']["#{promo['Id']}"].include?(my_teams[0]))
    assert(@parsed_response['promo_teams']["#{promo['Id']}"].include?(my_teams[1]))
    refute_empty(@parsed_response['promo_teams']["#{promo_2['Id']}"])
    assert(@parsed_response['promo_teams']["#{promo_2['Id']}"].include?(my_teams_2[0]))
    refute(@parsed_response['promo_teams']["#{promo_2['Id']}"].include?(my_teams_2[1]))

    # Step 9
    assign_http(Config['turtle']['host'])

    user_params_2.delete('promo_team')
    user_params_2['promo_teams'] = my_teams_2

    put '/usr', user_params_2, headers
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    assert_equal(@parsed_response['active_promo_id'], @parsed_response['promo']['id'])
    assert(my_teams_2.include?(@parsed_response['promo_team']), @parsed_response['promo_team'])
    assert(@parsed_response['promo_teams'].include?(my_teams_2[0]), @parsed_response['promo_teams'])
    assert(@parsed_response['promo_teams'].include?(my_teams_2[1]), @parsed_response['promo_teams'])

    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => promo_2['Id'],
    }.merge(api_key)

    get '/pros/dashboard', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['user_stats'])
    assert(my_teams_2.include?(@parsed_response['user_stats']['team_name']), @parsed_response['user_stats']['team_name'])
    assert(@parsed_response['user_stats']['team_names'].include?(my_teams_2[0]), @parsed_response['promo_teams'])
    assert(@parsed_response['user_stats']['team_names'].include?(my_teams_2[1]), @parsed_response['promo_teams'])

    # Step 10
    get_user_info(@user.oauth_token, { 'include_promos' => true })
    assert_response(@response, :success)
    refute_empty(@parsed_response['promos'], @parsed_response)
    assert_equal(@parsed_response['active_promo_id'], @parsed_response['promos'][0]['id'])
    profile_promo = @parsed_response['promos'].find { |p| p['id'] == promo['Id'] }
    assert(profile_promo['team_names'].include?(my_teams[0]), @parsed_response['promos'])
    assert(profile_promo['team_names'].include?(my_teams[1]), @parsed_response['promos'])
    refute_empty(@parsed_response['promo_teams']["#{promo['Id']}"])
    assert(@parsed_response['promo_teams']["#{promo['Id']}"].include?(my_teams[0]))
    assert(@parsed_response['promo_teams']["#{promo['Id']}"].include?(my_teams[1]))
    refute_empty(@parsed_response['promo_teams']["#{promo_2['Id']}"])
    assert(@parsed_response['promo_teams']["#{promo_2['Id']}"].include?(my_teams_2[0]))
    assert(@parsed_response['promo_teams']["#{promo_2['Id']}"].include?(my_teams_2[1]))

    # Step 11
    promo_params = {
        'promo_id' => promo['Id'],
        'access_token' => @user.oauth_token,
    }.merge(api_key)

    get '/pros/leaderboard', promo_params
    assert_response(@response, :success)
    assert_equal(promo['Id'].to_s, @parsed_response['original_request']['promo_id'])
    assert(@parsed_response['promo'], @parsed_response)
    assert_equal(promo['Id'] , @parsed_response['promo']['id'], @parsed_response['promo'])
    refute_empty(@parsed_response['promo']['team_names'], @parsed_response['promo'])
    assert(@parsed_response['leaderboard'], @parsed_response)
    assert(@parsed_response['top_users'], @parsed_response)

    promo_params['promo_id'] = promo_2['Id']

    get '/pros/leaderboard', promo_params
    assert_response(@response, :success)
    assert_equal(promo_2['Id'].to_s, @parsed_response['original_request']['promo_id'])
    leaderboard_promo_2 = @parsed_response
    assert(leaderboard_promo_2['promo'], leaderboard_promo_2)
    assert_equal(promo_2['Id'] , leaderboard_promo_2['promo']['id'], leaderboard_promo_2['promo'])
    refute_empty(leaderboard_promo_2['promo']['team_names'], leaderboard_promo_2['promo'])
    assert(leaderboard_promo_2['leaderboard'], leaderboard_promo_2)
    assert(leaderboard_promo_2['top_users'], leaderboard_promo_2)

    # Step 12
    promo_params = {
        'user_in_promo' => true,
        'access_token' => @user.oauth_token,
    }.merge(api_key)

    get '/pros/leaderboard', promo_params
    assert_response(@response, :success)
    assert_equal('true', @parsed_response['original_request']['user_in_promo'])
    assert(@parsed_response['promo'], @parsed_response)
    assert_equal(promo_2['Id'], @parsed_response['promo']['id'], @parsed_response['promo'])
    refute_empty(@parsed_response['promo']['team_names'], @parsed_response['promo'])
    assert(@parsed_response['leaderboard'], @parsed_response)
    assert_equal(leaderboard_promo_2['leaderboard'], @parsed_response['leaderboard'])
    assert(@parsed_response['top_users'], @parsed_response)
    assert_equal(leaderboard_promo_2['top_users'], @parsed_response['top_users'])
  end

  ##
  # Test points from hypersuggest/mb endpoint
  # AS-7173 | YP4S - Maintain active promos for a user (hypersuggest)
  #
  # Steps
  # Setup
  # 1. Verify response for valid category within promo
  # 2. Verify response for invalid category for promo
  # 3. Verify response for valid category within promo for active promo check
  def test_hypersuggest_mb_returns_points_with_promo_id
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    heading_text = 'Attorneys'
    heading_code = '8000177'
    points = @active_promo_points['points']
    review = points['ReviewPoints'].find {|r| r['HeadingCode'] == heading_code}
    photo = points['PhotoPoints'].find {|p| p['HeadingCode'] == heading_code}
    total_review_points = review['TotalPoints']
    total_photo_points = photo['TotalPoints']

    # Step 1
    assign_http(Config['panda']['host'])

    params = {
        'app_id' => 'WEB',
        'oauth_token' => @user.oauth_token,
        'ptid' => 'API',
        'rid' => 'Test',
        'vrid' => 'ABC123',
        'promo_id' => @promo['Id'],
        'g' => 'glendale, ca',
        'q' => 'law'
    }

    get '/hypersuggest/mb', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Suggestions'], "No results returned: '/hypersuggest/mb', #{params} -- #{@parsed_response}")

    @parsed_response['Suggestions'].each do |suggestion|
      assert(suggestion['Int_Xxid'], suggestion)
      assert(suggestion['Rateable'] == 1, suggestion)
      assert(suggestion['Promo'], suggestion)

      ht = suggestion['AllHeadingText'].include?(heading_text)
      hc = suggestion['AllHeadingCode'].include?(heading_code)

      unless suggestion['Promo']['PointsTier'] == 0
        if ht && hc
          suggestion_photo_points = suggestion['Promo']['PhotoPoints']
          suggestion_review_points = suggestion['Promo']['ReviewPoints']
          suggestion_total_points = suggestion['Promo']['TotalPoints']
          points_tier = suggestion['Promo']['PointsTier']

          assert_equal(total_photo_points, suggestion_photo_points)
          assert_equal(total_review_points, suggestion_review_points)
          assert_equal((suggestion_photo_points + suggestion_review_points), suggestion_total_points)
          assert(points_tier >= 1 && points_tier <= 3)
        end
      end
    end

    # Step 2
    params['q'] = 'piz'

    get '/hypersuggest/mb', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Suggestions'], @parsed_response)

    @parsed_response['Suggestions'].each do |suggestion|
      assert(suggestion['Int_Xxid'], suggestion)
      assert(suggestion['Promo'], suggestion)

      if suggestion['Rateable'] == 1
        if suggestion['Promo']['PointsTier'] == 0
          photo_points = suggestion['Promo']['PhotoPoints']
          review_points = suggestion['Promo']['ReviewPoints']
          total_points = suggestion['Promo']['TotalPoints']

          assert(photo_points != 0)
          assert(review_points != 0)
          assert_equal((photo_points + review_points), total_points)
        end
      end
    end

    # Step 3
    assign_http(Config['panda']['host'])

    params = {
        'app_id' => 'WEB',
        'oauth_token' => @user.oauth_token,
        'ptid' => 'API',
        'rid' => 'Test',
        'vrid' => 'ABC123',
        'user_in_promo' => true,
        'g' => 'glendale, ca',
        'q' => 'law'
    }

    get '/hypersuggest/mb', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Suggestions'], "No results returned: '/hypersuggest/mb', #{params} -- #{@parsed_response}")

    @parsed_response['Suggestions'].each do |suggestion|
      assert(suggestion['Int_Xxid'], suggestion)
      assert(suggestion['Rateable'] == 1, suggestion)
      assert(suggestion['Promo'], suggestion)

      ht = suggestion['AllHeadingText'].include?(heading_text)
      hc = suggestion['AllHeadingCode'].include?(heading_code)

      unless suggestion['Promo']['PointsTier'] == 0
        if ht && hc
          suggestion_photo_points = suggestion['Promo']['PhotoPoints']
          suggestion_review_points = suggestion['Promo']['ReviewPoints']
          suggestion_total_points = suggestion['Promo']['TotalPoints']
          points_tier = suggestion['Promo']['PointsTier']

          assert_equal(total_photo_points, suggestion_photo_points)
          assert_equal(total_review_points, suggestion_review_points)
          assert_equal((suggestion_photo_points + suggestion_review_points), suggestion_total_points)
          assert(points_tier >= 1 && points_tier <= 3)
        end
      end
    end
  end

  ##
  # AS-7125 | Handle recalculation of points and price when image is deleted or suppressed
  #
  # Steps:
  # Setup
  # 1. Get the base dashboard stats
  # 2. User uploads a photo for the promo
  # 3. Verify the dashboard user and promo stats increase
  # 4. Delete the photo using /b_image/:sha1/int_xxid/:id/report endpoint
  # 5. Verify the dashboard user and promo stats return to the initial values
  def test_recalculation_for_removing_photo_from_promo
    # Setup
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    business_listings = get_promo_listings
    int_xxid = business_listings.sample['Int_Xxid']

    # Step 1
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    promo = @parsed_response['promo']
    user_base_stats = @parsed_response['user_stats']
    assert_equal(0, user_base_stats['photo_count'])
    assert_equal(0, user_base_stats['contributed_points'])

    [1,2,3,4,5,6].shuffle.each do |reason|
      # Step 2
      upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid, @user, @active_promo_id)
      assert_response(@response, :success)
      sha1 = @parsed_response['id']

      # Step 3
      assign_http(Config['snake']['host'])

      params = {
          'access_token' => @user.oauth_token,
          'promo_id' => @active_promo_id,
          'api_key' => @api_key
      }

      get '/pros/dashboard', params
      assert_response(@response, :success)
      assert_equal(@active_promo_id, @parsed_response['promo']['id'])
      updated_promo = @parsed_response['promo']
      refute_equal(promo['photo_count'], updated_promo['photo_count'])
      refute_equal(promo['contributed_points'], updated_promo['contributed_points'])
      updated_user_base_stats = @parsed_response['user_stats']
      refute_equal(0, updated_user_base_stats['photo_count'])
      refute_equal(0, updated_user_base_stats['contributed_points'])

      # Step 4
      assign_http(Config['monkey']['host'])

      params = {
          'api_key' => Config['monkey']['api_key'],
          'reason' => reason,
          'oauth_token' => @user.oauth_token,
          'metadata' => {
              'user_type' => 'xx'
          },
          'override' => true
      }

      post "/b_image/#{sha1}/int_xxid/#{int_xxid}/report", params
      assert_response(@response, :success)

      # Step 5
      assign_http(Config['snake']['host'])

      params = {
          'access_token' => @user.oauth_token,
          'promo_id' => @active_promo_id,
          'api_key' => @api_key
      }

      get '/pros/dashboard', params
      assert_response(@response, :success)
      assert_equal(@active_promo_id, @parsed_response['promo']['id'])
      assert_equal(promo['photo_count'], @parsed_response['promo']['photo_count'])
      assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'])
      assert_equal(0, @parsed_response['user_stats']['photo_count'])
      assert_equal(0, @parsed_response['user_stats']['contributed_points'])

      if reason == 6
        assign_http(Config['monkey']['host'])

        params = {
            'api_key' => Config['monkey']['api_key'],
            'reason' => reason,
            'oauth_token' => @user.oauth_token,
            'metadata' => {
                'user_type' => 'xx'
            }
        }

        post "/b_image/#{sha1}/int_xxid/#{int_xxid}/report", params
        assert_response(@response, :client_error)
        assert_equal('ImageAlreadyHidden', @parsed_response['error'])
        assert_equal('ImageAlreadyHidden', @parsed_response['message'])
      end
    end
  end

  ##
  # AS-7125 | Handle recalculation of points and price when image is deleted or suppressed
  #
  # Steps:
  # Setup
  # 1. Get the base dashboard stats
  # 2. User uploads a photo for the promo for two different businesses
  # 3. Verify the dashboard user and promo stats increase
  # 4. Delete the photo using /b_image/:sha1/int_xxid/:id/report endpoint with 1, 2, or 3
  # 5. Verify the dashboard user and promo stats return to the initial values
  def test_recalc_removing_dup_photo_from_promo
    # Setup
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 2
    business_listings = get_promo_listings
    int_xxid_1 = business_listings[0]['Int_Xxid']
    int_xxid_2 = business_listings[1]['Int_Xxid']

    # Step 1
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    promo = @parsed_response['promo']
    user_base_stats = @parsed_response['user_stats']
    assert_equal(0, user_base_stats['photo_count'])
    assert_equal(0, user_base_stats['contributed_points'])

    # Step 2
    image = generate_random_image

    upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid_1, @user, @active_promo_id, image)
    assert_response(@response, :success)
    sha1 = @parsed_response['id']

    upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid_2, @user, @active_promo_id, image)
    assert_response(@response, :success)

    # Step 3
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    updated_promo = @parsed_response['promo']
    refute_equal(promo['photo_count'], updated_promo['photo_count'])
    refute_equal(promo['contributed_points'], updated_promo['contributed_points'])
    updated_user_base_stats = @parsed_response['user_stats']
    refute_equal(0, updated_user_base_stats['photo_count'])
    refute_equal(0, updated_user_base_stats['contributed_points'])

    # Step 4
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => Config['monkey']['api_key'],
        'reason' => [1,2,3].sample,
        'oauth_token' => @user.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    post "/b_image/#{sha1}/int_xxid/#{int_xxid_1}/report", params
    assert_response(@response, :success)

    # Step 5
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal(promo['photo_count'], @parsed_response['promo']['photo_count'])
    assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'])
    assert_equal(0, @parsed_response['user_stats']['photo_count'])
    assert_equal(0, @parsed_response['user_stats']['contributed_points'])
  end

  ##
  # AS-7125 | Handle recalculation of points and price when image is deleted or suppressed
  #
  # Steps:
  # Setup
  # 1. Get the base dashboard stats
  # 2. User uploads a photo for the promo for two different businesses
  # 3. Verify the dashboard user and promo stats increase
  # 4. Delete the photo using /b_image/:sha1/int_xxid/:id/report endpoint with 4 or 5 with override false
  # 5. Verify the dashboard user and promo stats return to the same updated values
  # 6. Delete the photo using /b_image/:sha1/int_xxid/:id/report endpoint with 4 or 5 with override true
  # 7. Verify the dashboard user and promo stats return to the initial values
  # 8. Delete the photo using /b_image/:sha2/int_xxid/:id/report endpoint with 1, 2, 3
  # 9. Verify the dashboard user and promo stats remain at initial values
  def test_recalc_removing_dup_photo_from_promo_for_diff_reasons
    # Setup
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    business_listings = get_promo_listings
    int_xxid_1 = business_listings[0]['Int_Xxid']
    int_xxid_2 = business_listings[1]['Int_Xxid']

    search_opts = { 'promo_id' => @active_promo_id }

    get_consumer_business_resp(int_xxid_1, search_opts)
    assert_response(@response, :success)
    int_xxid_1_promo = @parsed_response['Business']['Promo']

    # Step 1
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    promo = @parsed_response['promo']
    user_base_stats = @parsed_response['user_stats']
    assert_equal(0, user_base_stats['photo_count'])
    assert_equal(0, user_base_stats['contributed_points'])

    # Step 2
    image = generate_random_image

    upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid_1, @user, @active_promo_id, image)
    assert_response(@response, :success)
    sha1 = @parsed_response['id']

    upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid_2, @user, @active_promo_id, image)
    assert_response(@response, :success)
    sha2 = @parsed_response['id']

    # Step 3
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    updated_promo = @parsed_response['promo']
    refute_equal(promo['photo_count'], updated_promo['photo_count'])
    refute_equal(promo['contributed_points'], updated_promo['contributed_points'])
    updated_user_base_stats = @parsed_response['user_stats']
    refute_equal(0, updated_user_base_stats['photo_count'])
    refute_equal(0, updated_user_base_stats['contributed_points'])

    # Step 4
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => Config['monkey']['api_key'],
        'reason' => [4,5].sample,
        'oauth_token' => @user.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        },
        'override' => false
    }

    post "/b_image/#{sha1}/int_xxid/#{int_xxid_1}/report", params
    assert_response(@response, :success)

    # Step 5
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal(updated_promo['photo_count'], @parsed_response['promo']['photo_count'])
    assert_equal(updated_promo['contributed_points'], @parsed_response['promo']['contributed_points'])
    refute_equal(0, @parsed_response['user_stats']['photo_count'])
    refute_equal(0, @parsed_response['user_stats']['contributed_points'])

    # Step 6
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => Config['monkey']['api_key'],
        'reason' => [4,5].sample,
        'oauth_token' => @user.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        },
        'override' => true
    }

    post "/b_image/#{sha1}/int_xxid/#{int_xxid_1}/report", params
    assert_response(@response, :success)

    # Step 7
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal((updated_promo['photo_count'] - 1), @parsed_response['promo']['photo_count'])
    assert_equal((updated_promo['contributed_points'] - int_xxid_1_promo['PhotoPoints']), @parsed_response['promo']['contributed_points'])
    refute_equal(0, @parsed_response['user_stats']['photo_count'])
    refute_equal(0, @parsed_response['user_stats']['contributed_points'])

    # Step 8
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => Config['monkey']['api_key'],
        'reason' => [1,2,3].sample,
        'oauth_token' => @user.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    post "/b_image/#{sha2}/int_xxid/#{int_xxid_2}/report", params
    assert_response(@response, :success)

    # Step 9
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal(promo['photo_count'], @parsed_response['promo']['photo_count'])
    assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'])
    assert_equal(0, @parsed_response['user_stats']['photo_count'])
    assert_equal(0, @parsed_response['user_stats']['contributed_points'])
  end

  ##
  # AS-7125 | Handle recalculation of points and price when image is deleted or suppressed
  #
  # Steps:
  # Setup
  # 1. Get the base dashboard stats
  # 2. User upload a photo for the promo for a businesses
  # 3. Verify the dashboard user and promo stats increase
  # 4. Delete the photo using /b_image/:sha1/int_xxid/:id/report endpoint with 4 or 5 with override false
  # 5. Verify the dashboard user and promo stats return to the same updated values
  # 6. Delete the photo using /b_image/:sha1/int_xxid/:id/report endpoint with 4 or 5 with override false
  # 7. Verify the dashboard user and promo stats return to the same updated values
  # 8. Delete the photo using /b_image/:sha1/int_xxid/:id/report endpoint with 4 or 5 with override false
  # 9. Verify the dashboard user and promo stats return to initial values
  def test_recalc_removing_dup_photo_from_promo_for_multi_flagged
    # Setup
    @user1 = setup_user
    @user2 = setup_user
    @user3 = setup_user
    @user4 = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user1.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    headers = { 'Authorization' => "Bearer #{@user2.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    business_listings = get_promo_listings
    int_xxid = business_listings.sample['Int_Xxid']

    # Step 1
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user1.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    promo = @parsed_response['promo']
    user_base_stats = @parsed_response['user_stats']
    assert_equal(0, user_base_stats['photo_count'])
    assert_equal(0, user_base_stats['contributed_points'])

    # Step 2
    image = generate_random_image

    upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid, @user1, @active_promo_id, image)
    assert_response(@response, :success)
    sha1 = @parsed_response['id']

    # Step 3
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user1.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    updated_promo = @parsed_response['promo']
    refute_equal(promo['photo_count'], updated_promo['photo_count'])
    refute_equal(promo['contributed_points'], updated_promo['contributed_points'])
    updated_user_base_stats = @parsed_response['user_stats']
    refute_equal(0, updated_user_base_stats['photo_count'])
    refute_equal(0, updated_user_base_stats['contributed_points'])

    # Step 4
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => Config['monkey']['api_key'],
        'reason' => [4,5].sample,
        'oauth_token' => @user2.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    post "/b_image/#{sha1}/int_xxid/#{int_xxid}/report", params
    assert_response(@response, :success)

    # Step 5
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user1.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal(updated_promo['photo_count'], @parsed_response['promo']['photo_count'])
    assert_equal(updated_promo['contributed_points'], @parsed_response['promo']['contributed_points'])
    refute_equal(0, @parsed_response['user_stats']['photo_count'])
    refute_equal(0, @parsed_response['user_stats']['contributed_points'])

    # Step 6
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => Config['monkey']['api_key'],
        'reason' => [4,5].sample,
        'oauth_token' => @user3.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    post "/b_image/#{sha1}/int_xxid/#{int_xxid}/report", params
    assert_response(@response, :success)

    # Step 7
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user1.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal(updated_promo['photo_count'], @parsed_response['promo']['photo_count'])
    assert_equal(updated_promo['contributed_points'], @parsed_response['promo']['contributed_points'])
    refute_equal(0, @parsed_response['user_stats']['photo_count'])
    refute_equal(0, @parsed_response['user_stats']['contributed_points'])

    # Step 8
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => Config['monkey']['api_key'],
        'reason' => [4,5].sample,
        'oauth_token' => @user4.oauth_token,
        'metadata' => {
            'user_type' => 'xx'
        }
    }

    post "/b_image/#{sha1}/int_xxid/#{int_xxid}/report", params
    assert_response(@response, :success)

    # Step 9
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user1.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal(promo['photo_count'], @parsed_response['promo']['photo_count'])
    assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'])
    assert_equal(0, @parsed_response['user_stats']['photo_count'])
    assert_equal(0, @parsed_response['user_stats']['contributed_points'])
  end

  ##
  # Steps:
  # Setup
  # 1. Get the base dashboard stats
  # 2. User uploads a photo for the promo
  # 3. Verify the dashboard user and promo stats increase
  # 4. Delete the photo using /b_image/:sha1/int_xxid/:id/report endpoint
  # 5. Verify the dashboard user and promo stats return to the initial values
  def test_recalculation_for_removing_review_from_promo
    # Setup
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    business_listings = get_promo_listings
    int_xxid = business_listings.sample['Int_Xxid']

    # Step 1
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    promo = @parsed_response['promo']
    user_base_stats = @parsed_response['user_stats']
    assert_equal(0, user_base_stats['review_count'])
    assert_equal(0, user_base_stats['contributed_points'])

    # Step 2
    assign_http(Config['panda']['host'])

    params = {
        'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
        'source' => 'XX3',
        'subject' => 'Review made by API',
        'value' => rand(1..5),
        'listing_id' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'promo_id' => @active_promo_id
    }

    put '/usr/reviews', params
    assert_response(@response, :success)
    rating_id = @parsed_response['RatingID']

    # Step 3
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    updated_promo = @parsed_response['promo']
    refute_equal(promo['review_count'], updated_promo['review_count'])
    refute_equal(promo['contributed_points'], updated_promo['contributed_points'])
    updated_user_base_stats = @parsed_response['user_stats']
    refute_equal(0, updated_user_base_stats['review_count'])
    refute_equal(0, updated_user_base_stats['contributed_points'])

    # Step 4
    assign_http(Config['panda']['host'])

    params = { 'oauth_token' => @user.oauth_token }

    delete "/usr/reviews/#{rating_id}", params
    assert_response(@response, :success)

    # Step 5
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal(promo['review_count'], @parsed_response['promo']['review_count'])
    assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'])
    assert_equal(0, @parsed_response['user_stats']['review_count'])
    assert_equal(0, @parsed_response['user_stats']['contributed_points'])
  end

  ##
  # AS-7147 | PTA: Implement taxonomy-based group categories
  #
  # Setup
  # Steps:
  # 1. Verify photo & review price for each int_xxid (MIP)
  # 2. Verify the taxonomy pricing structure:
  #------------------------------------------------------------------------------#
  # G = Group, which means heading codes listed under that group return the same
  #     points as the parent unless they also are a group
  #
  # RESTAURANTS - ASIAN RESTAURANTS(G) - CHINESE RESTAURANTS
  #                                    \ JAPANESE RESTAURANTS(G) - SUSHI BAR
  #------------------------------------------------------------------------------#
  def test_promo_cache_taxonomy_for_defined_groups
    # Setup
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    promo_points = @active_promo_points['points']
    refute_empty(promo_points['ReviewPoints'], promo_points)
    refute_empty(promo_points['PhotoPoints'], promo_points)

    # Step 1
    int_xxids = {
        'asian' => 10133136,
        'japanese' => 496310697,
        'chinese' => 11132682,
        'sushi' => 3005370,
    }

    businesses = {}
    search_opts = { 'promo_id' => @active_promo_id }
    int_xxids.each_value do |int_xxid|
      get_consumer_business_resp(int_xxid, search_opts)
      assert_response(@response, :success)
      business = @parsed_response['Business']

      review_points = 0
      photo_points = 0
      if int_xxid == int_xxids['asian'] || int_xxid == int_xxids['japanese']
        check = promo_points['ReviewPoints'].find { |r| r['HeadingCode'] == business['HeadingCode'] }
        if check && check['Points']
          review_points = check['Points']
        end

        check = promo_points['PhotoPoints'].find { |r| r['HeadingCode'] == business['HeadingCode'] }
        if check && check['Points']
          photo_points = check['Points']
        end
      else
        business['AllHeadingCodes'].each do |ahc|
          check = promo_points['ReviewPoints'].find { |r| r['HeadingCode'] == ahc }
          if check && check['Points']
            if check['Points'] > review_points
              review_points = check['Points']
            end
          end

          check = promo_points['PhotoPoints'].find { |p| p['HeadingCode'] == ahc }
          if check && check['Points']
            if check['Points'] > photo_points
              photo_points = check['Points']
            end
          end
        end
      end

      name = business['HeadingText'].gsub(' Restaurants', '').gsub(' Menus', '').gsub(' Bars', '')

      points = {
          'Promo' => {
              'ReviewPoints' => review_points,
              'PhotoPoints' => photo_points,
          }
      }
      businesses[name] = points
    end
    refute_empty(businesses)

    # Step 2
    asian_review = businesses['Asian']['Promo']['ReviewPoints']
    asian_photo = businesses['Asian']['Promo']['PhotoPoints']
    chinese_review = businesses['Chinese']['Promo']['ReviewPoints']
    chinese_photo = businesses['Chinese']['Promo']['PhotoPoints']
    japanese_review = businesses['Japanese']['Promo']['ReviewPoints']
    japanese_photo = businesses['Japanese']['Promo']['PhotoPoints']
    sushi_review = businesses['Sushi']['Promo']['ReviewPoints']
    sushi_photo = businesses['Sushi']['Promo']['PhotoPoints']

    # Asian(G) and Chinese Restaurants should match
    assert_equal(asian_review, chinese_review, "Expected Match - asian_review: #{asian_review}, chinese_review: #{chinese_review}")
    assert_equal(asian_photo, chinese_photo, "Expected Match - asian_photo: #{asian_photo}, chinese_photo: #{chinese_photo}")
    # Asian and Japanese(G) Restaurants should not match
    refute_equal(asian_review, japanese_review, "Expected Not to Match - asian_review: #{asian_review}, japanese_review: #{japanese_review}")
    refute_equal(asian_photo, japanese_photo, "Expected Not to Match - asian_photo: #{asian_photo}, japanese_photo: #{japanese_photo}")
    # Japanese(G) and Sushi Restaurants should match
    assert_equal(japanese_review, sushi_review, "Expected Match - japanese_review: #{japanese_review}, sushi_review: #{sushi_review}")
    assert_equal(japanese_photo, sushi_photo, "Expected Match - japanese_photo: #{japanese_photo}, sushi_photo: #{sushi_photo}")
    # Chinese and Sushi Restaurants should not match
    refute_equal(chinese_review, sushi_review, "Expected Not to Match - chinese_review: #{chinese_review}, sushi_review: #{sushi_review}")
    refute_equal(chinese_photo, sushi_photo, "Expected Not to Match - chinese_photo: #{chinese_photo}, sushi_photo: #{sushi_photo}")
  end

  ##
  # AS-7157 | Handle recalculation for review deletes
  #
  # Steps:
  # Setup
  # 1. Get the base dashboard stats
  # 2. User uploads three reviews for the promo
  # 3. Verify the dashboard user and promo stats increase
  # 4. Delete all three reviews
  # 5. Verify the dashboard user and promo stats return to the initial values
  def test_recalculation_for_removing_reviews_from_promo
    # Setup
    opts = {
        'first_name' => 'Maximus',
        'last_name' => 'Meridius'
    }

    @user = setup_user(opts)

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    business_listings = get_promo_listings

    businesses = []
    total_review_points = 0
    count = 0
    search_opts = { 'promo_id' => @active_promo_id }
    3.times do
      get_consumer_business_resp(business_listings[count]['Int_Xxid'], search_opts)
      assert_response(@response, :success)
      businesses << @parsed_response['Business']
      total_review_points += @parsed_response['Business']['Promo']['ReviewPoints']
      count += 1
    end
    assert_equal(3, businesses.length)
    refute_equal(0, total_review_points)

    # Step 1
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    promo = @parsed_response['promo']
    user_base_stats = @parsed_response['user_stats']
    assert_equal(0, user_base_stats['photo_count'])
    assert_equal(0, user_base_stats['review_count'])
    assert_equal(0, user_base_stats['contributed_points'])

    # Step 2
    rating_ids = []
    businesses.each do |business|
      params = {
          'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
          'source' => 'XX3',
          'subject' => 'Review made by API',
          'value' => rand(1..5),
          'listing_id' => business['Int_Xxid'],
          'oauth_token' => @user.oauth_token,
          'promo_id' => @active_promo_id,
          'api_key' => @api_key
      }

      # Use Int_Xxid at least once to check this doesn't fail | AS-7246
      if rating_ids.length == 2
        params.delete('listing_id')
        params['int_xxid'] = business['Int_Xxid']
      end

      put '/snake/usr/reviews', params
      assert_response(@response, :success)
      assert(@parsed_response['ratings'], @parsed_response)
      assert(@parsed_response['ratings']['RatingID'], @parsed_response['ratings'])
      rating_ids << @parsed_response['ratings']['RatingID']

      assert(@parsed_response['ratings']['Rating'], @parsed_response['ratings'])
      rating = @parsed_response['ratings']['Rating']
      assert_equal(@user.id, rating['AuthorUserId'])
    end

    # Step 3
    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    updated_user_base_stats = @parsed_response['user_stats']
    assert_equal(user_base_stats['photo_count'], updated_user_base_stats['photo_count'])
    assert_equal(3, updated_user_base_stats['review_count'])
    assert_equal((user_base_stats['contributed_points'] + total_review_points), updated_user_base_stats['contributed_points'],
                 "Expected user contributed points to equal: #{total_review_points} - #{updated_user_base_stats}")
    updated_promo = @parsed_response['promo']
    assert_equal((promo['review_count'] + 3), updated_promo['review_count'])
    assert_equal((promo['contributed_points'] + total_review_points), updated_promo['contributed_points'],
                 "Expected promo contributed points to equal: #{(promo['contributed_points'] + total_review_points)} - #{updated_promo['contributed_points']}")

    # Step 4
    assign_http(Config['panda']['host'])

    params = {
        'oauth_token' => @user.oauth_token,
        'promo_id' => @active_promo_id
    }

    delete "/usr/reviews/#{rating_ids[0]}", params
    assert_response(@response, :success)

    delete "/usr/#{@user.id}/rats/#{rating_ids[1]}", {}
    assert_response(@response, :success)

    delete "/rats/#{rating_ids[2]}", params
    assert_response(@response, :success)

    # Step 5
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal(promo['photo_count'], @parsed_response['promo']['photo_count'])
    assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'])
    assert_equal(0, @parsed_response['user_stats']['photo_count'])
    assert_equal(0, @parsed_response['user_stats']['contributed_points'])
  end

  ##
  # AS-7236 | Add points to /cons/search endpoint
  #
  # Steps
  # 1. Verify consumer search response contains points for the promo
  def test_promo_points_display_on_consumer_search
    # Step 1
    opts = { 'promo_id' => @active_promo_id }

    get_consumer_search_resp('restaurants', 'los angeles, ca', opts)
    assert_response(@response, :success)
    refute_empty(@parsed_response['SearchResult']['BusinessListings'])

    @parsed_response['SearchResult']['BusinessListings'].each do |business|
      assert(business['Promo'])
      message = "Expected /cons/search response returning int_xxid: #{business['Int_Xxid']}, promo points to be greater than zero: #{business['Promo']}"
      assert(business['Promo']['PhotoPoints'] > 0, message)
      assert(business['Promo']['ReviewPoints'] > 0, message)
      assert_equal((business['Promo']['PhotoPoints'] + business['Promo']['ReviewPoints']), business['Promo']['TotalPoints'], message)
    end
  end

  ##
  # AS-7269 | PTA- Ability to Add and Update Points to Next Level File
  # AS-7287 | YP4S tools Support - Bulk update for points_to_price endpoints
  #
  # Steps:
  # Setup: Create a new promo, get existing points to price
  # 1. Verify response for creating points to price on promo
  # 2. Verify response for updating points to price on promo
  # 3. Verify response for promo points to price
  def test_add_update_points_next_level_promo
    # Setup
    assign_http(Config['panda']['host'])

    params = { 'start_date' => (Time.now.to_i - 1.day.to_i) }

    create_new_promo(params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo'])
    promo = @parsed_response['Promo']
    assert(promo['Code'], promo)
    assert(promo['Id'], promo)

    params = { 'promo_id' => promo['Id'] }

    get '/pros/points_to_price', params
    assert_response(@response, :success)
    assert_empty(@parsed_response['PointsToPrices'])

    # Step 1
    level = 1
    price = 50
    points = 100

    params = {
        'promo_id' => promo['Id'],
        'price' => price,
        'level' => level,
        'points'=> points
    }

    post '/pros/points_to_price' , params
    assert_response(@response, :success)
    assert(@parsed_response['PointsToPrice'])
    points_to_price = @parsed_response['PointsToPrice']
    assert(points_to_price['Id'])
    assert_equal(promo['Id'], points_to_price['PromoId'])
    assert_equal(points, points_to_price['Points'])
    assert_equal(level, points_to_price['Level'])
    assert_equal(price, points_to_price['Price'])

    # Step 2
    price += 50
    points += 100

    params = {
        'promo_id' => promo['Id'],
        'price' => price,
        'level' => level,
        'points'=> points,
        'points_to_price_id' => points_to_price['Id'],
    }

    put '/pros/points_to_price' , params
    assert_response(@response, :success)
    assert(@parsed_response['PointsToPrice'])
    updated_points_to_price = @parsed_response['PointsToPrice']
    assert_equal(points_to_price['Id'], updated_points_to_price['Id'])
    assert_equal(price, updated_points_to_price['Price'])
    assert_equal(level, updated_points_to_price['Level'])
    assert_equal(points, updated_points_to_price['Points'])

    # Step 3
    params = { 'promo_id' => promo['Id'] }

    get '/pros/points_to_price', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['PointsToPrices'])
    assert_equal(updated_points_to_price['Id'], @parsed_response['PointsToPrices'][0]['Id'])
    assert_equal(price, @parsed_response['PointsToPrices'][0]['Price'])
    assert_equal(level, @parsed_response['PointsToPrices'][0]['Level'])
    assert_equal(points, @parsed_response['PointsToPrices'][0]['Points'])

    # Step 4
    level += 1
    price += price
    points += points

    params = {
        'points_to_price' => [
            {
                'promo_id' => promo['Id'],
                'level' => level,
                'price' => price,
                'points'=> points,
            },
            {
                'promo_id' => promo['Id'],
                'level' => (level + 1),
                'price' => (price * 2),
                'points'=> (points * 2),
            },
            {
                'promo_id' => promo['Id'],
                'level' => (level + 2),
                'price' => (price * 4),
                'points'=> (points * 4),
            }
        ]
    }

    post '/pros/points_to_price/multi', params
    assert_response(@response, :success)
    assert(@parsed_response['PointsToPrice'])
    points_to_price = @parsed_response['PointsToPrice']
    points_to_price.each do |points_level|
      check = params['points_to_price'].find { |params| params['level'] == points_level['Level'] }
      if check
        assert(points_level['Id'])
        assert_equal(check['promo_id'], points_level['PromoId'])
        assert_equal(check['points'], points_level['Points'])
        assert_equal(check['price'], points_level['Price'])
      end
    end
  end

  ##
  # AS-7289 | PTA - Tool Support GET endpoint for base points
  # AS-7275 | Base points cannot be updated once promo started
  # AS-7273 | Base Points - Ability to add Base Points via file upload
  # AS-7329 | YP4S Tools support - Tools Uber cat support
  # AS-7385 | YP4S tools support - Remove the validation of promos start date for super admin support
  #
  # Steps:
  # Setup: Create a new active promo
  # 1. Add contents to the promo created in setup with & without super_user param
  # 2. Get all the content for the given promo
  # 3. Verify response for updating points with & without super_user param
  # 4. Verify response for adding points through bulk add /multi with & without super_user param
  # 5. Verify GET response for updated points
  def test_base_points_endpoints
    # Setup
    assign_http(Config['panda']['host'])

    promo_params = { 'start_date' => (Time.now - 1.day).to_i }

    create_new_promo(promo_params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo'])
    promo = @parsed_response['Promo']
    assert(promo['Code'], promo)
    assert(promo['Id'], promo)

    params = { 'promo_id' => promo['Id'] }

    get '/pros/base_points', params
    assert_response(@response, :success)
    assert_empty(@parsed_response['PromoPoints'])

    # Step 1
    count = 0
    promo_points = nil
    uber_cat = 'uber cat string'
    super_admin = { 'super_admin' => true }
    get_params = { 'promo_id' => promo['Id'] }

    points_params = [
        {
            'promo_id' => promo['Id'],
            'review_points' => 10,
            'photo_points' => 15,
            'heading_code'=> 8002625,
            'uber_cat' => uber_cat
        },
        {
            'promo_id' => promo['Id'],
            'review_points' => 20,
            'photo_points' => 25,
            'heading_code'=> 8002327,
            'uber_cat' => uber_cat
        }
    ]

    points_params.each do |params|
      post '/pros/points', params
      assert_response(@response, :client_error)
      assert_equal('PromoAlreadyActiveError', @parsed_response['error'])
      assert_equal('Oops! That promo is already active', @parsed_response['message'])

      post '/pros/points', params.merge!(super_admin)
      assert_response(@response, :success)
      promo_points = @parsed_response['PromoPoints']
      assert_equal(params['promo_id'], promo_points['PromoId'])
      assert_equal(params['review_points'], promo_points['ReviewPoints'])
      assert_equal(params['photo_points'], promo_points['PhotoPoints'])
      assert_equal(params['heading_code'].to_s, promo_points['HeadingCode'])
      assert_equal(params['uber_cat'], promo_points['UberCat'])
      count += 1

      # Step 2
      get '/pros/base_points', get_params
      assert_response(@response, :success)
      refute_empty(@parsed_response['PromoPoints'])
      promo_points_list = @parsed_response['PromoPoints']
      assert_equal(count, promo_points_list.length)
      promo_points_list.each do |list|
        if list['HeadingCode'].to_s == promo_points['HeadingCode']
          assert_equal(promo_points['ReviewPoints'], list['ReviewPoints'])
          assert_equal(promo_points['PhotoPoints'], list['PhotoPoints'])
        end
      end
    end

    # Step 3
    params = {
        'promo_id' => promo['Id'],
        'points_id' => promo_points['Id'],
        'review_points' => 50,
        'photo_points' => 150,
        'heading_code' => 8002625,
        'uber_cat' => uber_cat
    }

    put '/pros/points', params
    assert_response(@response, :client_error)
    assert_equal('PromoAlreadyActiveError', @parsed_response['error'])
    assert_equal('Oops! That promo is already active', @parsed_response['message'])

    put '/pros/points', params.merge!(super_admin)
    assert_response(@response, :success)
    promo_points = @parsed_response['PromoPoints']
    assert_equal(params['promo_id'], promo_points['PromoId'])
    assert_equal(params['review_points'], promo_points['ReviewPoints'])
    assert_equal(params['photo_points'], promo_points['PhotoPoints'])
    assert_equal(params['heading_code'].to_s, promo_points['HeadingCode'])
    assert_equal(params['uber_cat'], promo_points['UberCat'])

    # Steo 4
    params = {
        'promo_points' => [
            {
                'promo_id' => promo['Id'],
                'review_points' => 75,
                'photo_points' => 100,
                'heading_code' => 8002304,
                'uber_cat' => uber_cat
            },
            {
                'promo_id' => promo['Id'],
                'review_points' => 50,
                'photo_points' => 60,
                'heading_code' => 8004199,
                'uber_cat' => uber_cat
            }
        ]
    }

    post '/pros/points/multi', params
    assert_response(@response, :client_error)
    assert_equal('PromoAlreadyActiveError', @parsed_response['error'])
    assert_equal("#{promo['Id']} is already active", @parsed_response['message'])

    post '/pros/points/multi', params.merge!(super_admin)
    assert_response(@response, :success)
    assert(@parsed_response['PromoPoints'])
    @parsed_response['PromoPoints'].each do |points|
      assert(points['Id'])
      assert_equal(promo['Id'], points['PromoId'])
      param_points = params['promo_points'].find { |h| h['heading_code'].to_s == points['HeadingCode'] }
      if param_points
        assert_equal(param_points['review_points'], points['ReviewPoints'])
        assert_equal(param_points['photo_points'], points['PhotoPoints'])
        assert_equal(param_points['heading_code'].to_s, points['HeadingCode'])
        assert_equal(param_points['uber_cat'], points['UberCat'])
      end
    end

    # Step 5
    get '/pros/base_points', get_params
    assert_response(@response, :success)
    assert(@parsed_response['PromoPoints'])
    @parsed_response['PromoPoints'].each do |list|
      if list['Id'].to_s == promo_points['Id']
        assert_equal(promo_points['ReviewPoints'], list['ReviewPoints'])
        assert_equal(promo_points['PhotoPoints'], list['PhotoPoints'])
      end
    end
  end

  ##
  # AS-7270 | PTA - Ability to Upload single FAQ
  # AS-7283 | PTA - Add points to level to the promo/points/faq
  # AS-7291 | YP4S - Ability to bulk Upload FAQ file
  #
  # Steps:
  # Setup: Create a new promo, get existing points to price
  # 1. Verify response for creating single faq to promo
  # 2. Verify response for getting single faq to promo
  # 3. Verify response for uploading bulk faq to promo
  # 4. Verify response for getting updated faq to promo
  def test_create_points_faq_endpoints
    # Setup
    assign_http(Config['panda']['host'])

    params = { 'start_date' => (Time.now - 1.day).to_i }

    create_new_promo(params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo'])
    promo = @parsed_response['Promo']
    assert(promo['Code'], promo)
    assert(promo['Id'], promo)

    params = { 'promo_id' => promo['Id'] }

    get '/pros/points/faq', params
    assert_response(@response, :success)
    assert_empty(@parsed_response['Faqs'])

    # Step 1
    count = 0
    [
        {
            'promo_id' => promo['Id'],
            'faq' => 'THIS IS A FAQ',
            'faq_type' => 'type of faq',
            'points' => 100,
            'points_tier' => 1,
            'priority'=> 1
        },
        {
            'promo_id' => promo['Id'],
            'faq' => 'THIS IS A FAQ 2',
            'faq_type' => 'type of faq 2',
            'points' => 50,
            'points_tier' => 2,
            'priority'=> 2
        },
        {
            'promo_id' => promo['Id'],
            'faq' => 'THIS IS A FAQ 3',
            'faq_type' => 'type of faq 3',
            'points' => 30,
            'points_tier' => 3,
            'priority'=> 3
        }
    ].each do |params|
      post '/pros/points/faq' , params
      assert_response(@response, :success)
      assert(@parsed_response['PromoFaq'])
      post_faqs = @parsed_response['PromoFaq']
      assert(post_faqs['Id'])
      assert_equal(params['promo_id'], post_faqs['PromoId'])
      assert_equal(params['points'], post_faqs['Points'])
      assert_equal(params['faq'], post_faqs['Faq'])
      assert_equal(DateTime.parse(post_faqs['CreatedAt']).to_i, DateTime.parse(post_faqs['UpdatedAt']).to_i)
      assert_equal(params['faq_type'], post_faqs['FaqType'])
      assert_equal(params['points_tier'], post_faqs['PointsTier'])
      assert_equal(params['priority'], post_faqs['Priority'])
      count += 1

      # Step 2
      params = { 'promo_id' => promo['Id'] }

      get '/pros/points/faq', params
      assert_response(@response, :success)
      refute_empty(@parsed_response['Faqs'])
      get_faqs = @parsed_response['Faqs']
      assert_equal(count, get_faqs.length)
      get_faqs.each do |list|
        if list['Id'] == post_faqs['Id']
          assert_equal(post_faqs['PromoId'], list['PromoId'])
          assert_equal(post_faqs['Points'], list['Points'])
          assert_equal(post_faqs['Faq'], list['Faq'])
          assert_equal(DateTime.parse(post_faqs['CreatedAt']).to_i, DateTime.parse(list['CreatedAt']).to_i)
          assert_equal(DateTime.parse(post_faqs['UpdatedAt']).to_i, DateTime.parse(list['UpdatedAt']).to_i)
          assert_equal(post_faqs['FaqType'], list['FaqType'])
          assert_equal(post_faqs['PointsTier'], list['PointsTier'])
          assert_equal(post_faqs['Priority'], list['Priority'])
        end
      end
    end

    # Step 3
    params = {
        'promo_faqs' => [
            {
                'promo_id' => promo['Id'],
                'faq' => 'THIS IS A FAQ 4',
                'faq_type' => 'type of faq 4',
                'points' => 100,
                'points_tier' => 1,
                'priority'=> 1
            },
            {
                'promo_id' => promo['Id'],
                'faq' => 'THIS IS A FAQ 5',
                'faq_type' => 'type of faq 5',
                'points' => 90,
                'points_tier' => 1,
                'priority'=> 2
            },
            {
                'promo_id' => promo['Id'],
                'faq' => 'THIS IS A FAQ 6',
                'faq_type' => 'type of faq 6',
                'points' => 80,
                'points_tier' => 1,
                'priority'=> 3
            }
        ]
    }

    post '/pros/points/faq/multi' , params
    assert_response(@response, :success)
    assert(@parsed_response['PromoFaqs'], @parsed_response)
    post_multi_faqs = @parsed_response['PromoFaqs']
    post_multi_faqs.each do |post_faqs|
      assert(post_faqs['Id'])
      check = params['promo_faqs'].find { |params| params['priority'] == post_faqs['Priority'] }
      if check
        assert_equal(check['promo_id'], post_faqs['PromoId'])
        assert_equal(check['points'], post_faqs['Points'])
        assert_equal(check['faq'], post_faqs['Faq'])
        assert_equal(DateTime.parse(post_faqs['CreatedAt']).to_i, DateTime.parse(post_faqs['UpdatedAt']).to_i)
        assert_equal(check['faq_type'], post_faqs['FaqType'])
        assert_equal(check['points_tier'], post_faqs['PointsTier'])
        assert_equal(check['priority'], post_faqs['Priority'])
      end
    end

    # Step 4
    params = { 'promo_id' => promo['Id'] }

    get '/pros/points/faq', params
    assert_response(@response, :success)
    assert(@parsed_response['Faqs'])
    @parsed_response['Faqs'].each do |list|
      check = post_multi_faqs.find { |post_faqs| post_faqs['Id'] == list['Id'] }
      if check
        assert_equal(check['PromoId'], list['PromoId'])
        assert_equal(check['Points'], list['Points'])
        assert_equal(check['Faq'], list['Faq'])
        assert_equal(DateTime.parse(check['CreatedAt']).to_i, DateTime.parse(list['CreatedAt']).to_i)
        assert_equal(DateTime.parse(check['UpdatedAt']).to_i, DateTime.parse(list['UpdatedAt']).to_i)
        assert_equal(check['FaqType'], list['FaqType'])
        assert_equal(check['PointsTier'], list['PointsTier'])
        assert_equal(check['Priority'], list['Priority'])
      end
    end
  end

  ##
  # AS-7238 | PTA: Tools Order promo history by created_at desc
  #
  # Steps:
  # Setup: Create a new promo
  # 1. Update city field of existing promo
  # 2. Update state field of existing promo
  # 3. Update org_name field of existing promo
  # 4. Do promo lookup with history
  def test_order_promo_history_by_created_at_desc
    # Setup
    assign_http(Config['panda']['host'])

    params = {
        'city' => 'Dallas',
        'state' => 'TX',
        'org_name' => 'App For Service',
        'start_date' => (Time.now - 1.day).to_i
    }

    create_new_promo(params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo'])
    new_promo = @parsed_response['Promo']
    assert(new_promo['Id'])
    assert(new_promo['Code'], new_promo)
    code = new_promo['Code']
    assert(new_promo['Id'], new_promo)
    assert_equal(params['city'], new_promo['City'])
    assert_equal(params['state'], new_promo['State'])
    assert_equal(params['org_name'], new_promo['OrgName'])

    # Step 1
    params = {
        'promo_id' => new_promo['Id'],
        'code' => code,
        'city' => '"Glendale',
        'state' => 'TX',
        'org_name' => 'App For Service'
    }

    put '/pros', params
    assert_response(@response, :success)
    updated_promo= @parsed_response['Promo']
    assert_equal(code, new_promo['Code'])
    assert_equal(params['city'], updated_promo['City'])
    assert_equal(params['state'], updated_promo['State'])
    assert_equal(params['org_name'], updated_promo['OrgName'])
    assert(new_promo['Id'])

    #Step 2
    params = {
        'promo_id' => new_promo['Id'],
        'code' => code,
        'city' => 'Glendale',
        'state' => 'CA',
        'org_name' => 'App For Service'
    }

    put '/pros', params
    assert_response(@response, :success)
    updated_promo= @parsed_response['Promo']
    assert_equal(code, new_promo['Code'])
    assert_equal(params['city'], updated_promo['City'])
    assert_equal(params['state'], updated_promo['State'])
    assert_equal(params['org_name'], updated_promo['OrgName'])
    assert(new_promo['Id'])

    # Step 3
    params = {
        'promo_id' => new_promo['Id'],
        'code' => code,
        'city' => 'Glendale',
        'state' => 'CA',
        'org_name' => 'App at your Service'
    }

    put '/pros', params
    assert_response(@response, :success)
    updated_promo= @parsed_response['Promo']
    assert_equal(code, new_promo['Code'])
    assert_equal(params['city'], updated_promo['City'])
    assert_equal(params['state'], updated_promo['State'])
    assert_equal(params['org_name'], updated_promo['OrgName'])
    assert(new_promo['Id'])

    # Step 4
    params={
        'promo_id' => new_promo['Id'],
        'include_promo_history' => true
    }

    get '/pros/lookup', params
    assert_response(@response, :success)
    promo_response = @parsed_response['Promo']
    assert_equal(updated_promo['Id'], promo_response['Id'])
    assert_equal(updated_promo['Code'], promo_response['Code'])
    assert_equal(updated_promo['OrgName'], promo_response['OrgName'])
    assert_equal(updated_promo['City'], promo_response['City'])
    assert_equal(updated_promo['State'], promo_response['State'])
    promo_history  = @parsed_response['PromoHistory']
    refute_empty(promo_history)
    assert(promo_history.each_cons(2).all?{|i,j| i['CreatedAt'] >= j['CreatedAt']})
  end

  ##
  # AS-7307 | YP4S: Fix PUT /usr with no default_attributes set
  #
  # Steps:
  # Setup: Create a new promo, get existing points to price
  # 1. Verify response for user update on promo without default attributes
  def test_promo_with_no_default_attributes
    # Setup
    @user = setup_user

    assign_http(Config['panda']['host'])

    params = { 'start_date' => (Time.now - 1.day).to_i }

    create_new_promo(params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo'])
    promo = @parsed_response['Promo']
    assert(promo['Code'], promo)
    assert(promo['Id'], promo)

    # Step 1
    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    params = { 'promo_id' => promo['Id'] }
    params['promo_team'] = promo['TeamNames'].sample

    put '/usr', params, headers
    assert_response(@response, :success)
  end

  ##
  # AS-7311 | YP4S - Tools support with bulk base points with multipliers
  # AS-7276 | YP4S - Ability to add base points with multipliers
  # AS-7329 | YP4S Tools support - Tools Uber cat support
  #
  # Steps:
  # Setup: Create a new promo, add base points, points to price, price multipliers
  # 1. Verify response for GET /pros/multipliers is blank
  # 2. Verify response for POST /pros/multipliers/multi for bulk upload
  # 3. Verify response for POST /pros/multipliers for single upload
  # 4. Verify response for GET /pros/multipliers lists all uploads
  # 5. Verify response for PUT /pros/multipliers for single update
  # 6. Verify response for DELETE /pros/multipliers for single id
  # 7. Verify response for DELETE /pros/multipliers/multi for bulk ids
  def test_promo_multipliers
    # Setup
    assign_http(Config['panda']['host'])

    create_new_promo
    assert_response(@response, :success)
    assert(@parsed_response['Promo'])
    promo = @parsed_response['Promo']

    add_base_points_for_promo(promo['Id'])
    assert_response(@response, :success)
    assert(@parsed_response['PromoPoints'])
    promo_points = @parsed_response['PromoPoints']

    # Start the Promo
    params = {
        'promo_id' => promo['Id'],
        'start_date' => (DateTime.parse(promo['StartDate']) - 2.day).to_i,
    }

    put '/pros', params
    assert_response(@response, :success)
    assert(@parsed_response['Promo'])
    promo = @parsed_response['Promo']

    # Step 1
    params = { 'promo_id' => promo['Id'] }

    get '/pros/multipliers', params
    assert_response(@response, :success)
    assert_empty(@parsed_response['PromoMultipliers'])

    # Step 2
    moderator_id = unique_moderator_id
    start_date = (Time.now - 1.day).to_i
    end_date = (Time.now + rand(10..20).day).to_i

    uber_cat = 'uber cat string'
    multipliers = []
    promo_points.each do |points_group|
      if points_group['HeadingCode']
        multiplier = {
            'promo_id' => promo['Id'],
            'moderator_id' => moderator_id,
            'start_date' => start_date,
            'end_date' => end_date,
            'review_multiplier' => rand(2..5),
            'photo_multiplier' => rand(2..5),
            'heading_code' => points_group['HeadingCode'],
            'heading_text' => points_group['HeadingText'],
            'uber_cat' => uber_cat
        }

        multipliers << multiplier
      end
    end
    multiplier = multipliers.pop
    all_multipliers = multipliers
    all_multipliers << multiplier

    params = {
        'promo_id' => promo['Id'],
        'promo_multipliers' => multipliers
    }

    post '/pros/multipliers/multi', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['PromoMultipliers'])
    promo_multipliers = @parsed_response['PromoMultipliers']
    promo_multipliers.each do |multiplier|
      heading_check = multipliers.find { |m| m['heading_code'] == multiplier['HeadingCode'] }
      if heading_check
        assert_equal(heading_check['heading_text'], multiplier['HeadingText'])
        assert(multiplier['Id'])
        assert_equal(promo['Id'], multiplier['PromoId'])
        assert(multiplier['ReviewMultiplier'].between?(2,5))
        assert(multiplier['PhotoMultiplier'].between?(2,5))
        assert_equal(start_date, DateTime.parse(multiplier['StartDate']).to_i)
        assert_equal(end_date, DateTime.parse(multiplier['EndDate']).to_i)
        assert_equal(DateTime.parse(multiplier['CreatedAt']).to_i, DateTime.parse(multiplier['UpdatedAt']).to_i)
        assert_equal(moderator_id, multiplier['ModeratorId'])
        assert_equal(uber_cat, multiplier['UberCat'])
        assert_equal('Live', multiplier['Status'])
        assert_equal(0, multiplier['Deleted'])
      end
    end

    # Step 3
    post '/pros/multipliers', multiplier
    assert_response(@response, :success)
    assert(@parsed_response['PromoMultiplier'])
    promo_multiplier = @parsed_response['PromoMultiplier']
    assert_equal(multiplier['heading_code'], promo_multiplier['HeadingCode'])
    assert_equal(multiplier['heading_text'], promo_multiplier['HeadingText'])
    assert(promo_multiplier['Id'])
    assert_equal(promo['Id'], promo_multiplier['PromoId'])
    assert(promo_multiplier['ReviewMultiplier'].between?(2,5))
    assert(promo_multiplier['PhotoMultiplier'].between?(2,5))
    assert_equal(start_date, DateTime.parse(promo_multiplier['StartDate']).to_i)
    assert_equal(end_date, DateTime.parse(promo_multiplier['EndDate']).to_i)
    assert_equal(DateTime.parse(promo_multiplier['CreatedAt']).to_i, DateTime.parse(promo_multiplier['UpdatedAt']).to_i)
    assert_equal(moderator_id, promo_multiplier['ModeratorId'])
    assert_equal('Live', promo_multiplier['Status'])
    assert_equal(0, promo_multiplier['Deleted'])

    # Step 4
    params = { 'promo_id' => promo['Id'] }

    get '/pros/multipliers', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['PromoMultipliers'])
    @parsed_response['PromoMultipliers'].each do |multiplier|
      heading_check = all_multipliers.find { |m| m['heading_code'] == multiplier['HeadingCode'] }
      if heading_check
        assert_equal(heading_check['heading_text'], multiplier['HeadingText'])
        assert(multiplier['Id'])
        assert_equal(promo['Id'], multiplier['PromoId'])
        assert(multiplier['ReviewMultiplier'].between?(2,5))
        assert(multiplier['PhotoMultiplier'].between?(2,5))
        assert_equal(start_date, DateTime.parse(multiplier['StartDate']).to_i)
        assert_equal(end_date, DateTime.parse(multiplier['EndDate']).to_i)
        assert_equal(DateTime.parse(multiplier['CreatedAt']).to_i, DateTime.parse(multiplier['UpdatedAt']).to_i)
        assert_equal(moderator_id, multiplier['ModeratorId'])
        assert_equal('Live', multiplier['Status'])
        assert_equal(0, multiplier['Deleted'])
      end
    end

    # Step 5
    new_start_date = (Time.now + 5.day).to_i
    review_multiplier = multiplier['review_multiplier'] += 1
    photo_multiplier = multiplier['photo_multiplier'] += 1
    params = multiplier.dup
    params['promo_multiplier_id'] = promo_multiplier['Id']
    params['start_date'] = new_start_date
    params['review_multiplier'] = review_multiplier
    params['photo_multiplier'] = photo_multiplier
    params['uber_cat'] = uber_cat

    put '/pros/multipliers', params
    assert_response(@response, :success)
    assert(@parsed_response['PromoMultiplier'])
    update_promo_multiplier = @parsed_response['PromoMultiplier']
    assert_equal(multiplier['heading_code'], update_promo_multiplier['HeadingCode'])
    assert_equal(multiplier['heading_text'], update_promo_multiplier['HeadingText'])
    assert_equal(promo_multiplier['Id'], update_promo_multiplier['Id'])
    assert_equal(promo['Id'], update_promo_multiplier['PromoId'])
    assert_equal(review_multiplier, update_promo_multiplier['ReviewMultiplier'])
    assert_equal(photo_multiplier, update_promo_multiplier['PhotoMultiplier'])
    assert_equal(new_start_date, DateTime.parse(update_promo_multiplier['StartDate']).to_i)
    assert_equal(end_date, DateTime.parse(update_promo_multiplier['EndDate']).to_i)
    assert_equal(DateTime.now.utc.strftime('%Y%m%d').to_i, DateTime.parse(update_promo_multiplier['UpdatedAt']).strftime('%Y%m%d').to_i)
    assert_equal(moderator_id, update_promo_multiplier['ModeratorId'])
    assert_equal(uber_cat, update_promo_multiplier['UberCat'])
    assert_equal('Future', update_promo_multiplier['Status'])
    assert_equal(0, update_promo_multiplier['Deleted'])

    # Step 6
    params = {
        'promo_multiplier_id' => promo_multiplier['Id'],
        'moderator_id' => moderator_id
    }

    delete '/pros/multipliers', params
    assert_response(@response, :success)
    assert(@parsed_response['PromoMultiplier'])
    deleted_promo_multiplier = @parsed_response['PromoMultiplier']
    assert_equal(promo_multiplier['Id'], deleted_promo_multiplier['Id'])
    assert_equal(promo['Id'], deleted_promo_multiplier['PromoId'])
    assert_equal(moderator_id, deleted_promo_multiplier['ModeratorId'])
    assert_equal('Deleted', deleted_promo_multiplier['Status'])
    assert_equal(1, deleted_promo_multiplier['Deleted'])

    # Step 7
    multiplier_ids = promo_multipliers.map { |m| m['Id'] }

    params = {
        'promo_multiplier_ids' => multiplier_ids,
        'moderator_id' => moderator_id
    }

    delete '/pros/multipliers/multi', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['PromoMultipliers'])
    @parsed_response['PromoMultipliers'].each do |multiplier|
      assert_equal(promo['Id'], multiplier['PromoId'])
      assert_equal(moderator_id, multiplier['ModeratorId'])
      assert_equal('Deleted', multiplier['Status'])
      assert_equal(1, multiplier['Deleted'])
    end
  end

  ##
  # AS-7322 | YP4S - School image support on Dashboard
  #
  # Steps
  # Setup: User, Promo, Add user to Promo
  # 1. User of Promo uploads image for Promo
  # 2. Verify Promo Lookup returns current Sha uploaded
  # 3. User of Promo uploads new image for Promo
  # 4. Verify Promo Lookup returns current Sha uploaded
  # 4. Verify Promo Dashboard returns current Sha uploaded
  def test_add_promo_image_for_promo
    # Setup
    @user = setup_user

    assign_http(Config['panda']['host'])

    params = { 'start_date' => (Time.now - 1.day).to_i }

    create_new_promo(params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo'], @parsed_response)
    promo = @parsed_response['Promo']

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    params = { 'promo_id' => promo['Id'] }
    params['promo_team'] = promo['TeamNames'].sample

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 1
    params = { 'promo_id' => promo['Id'] }

    image_id = upload_image(@user.oauth_token, generate_random_image, params)
    assert(image_id)

    # Step 2
    assign_http(Config['panda']['host'])

    params = { 'promo_id' => promo['Id'] }

    get '/pros/lookup', params
    assert_response(@response, :success)
    assert(@parsed_response['Promo'], @parsed_response)
    assert_equal(image_id, @parsed_response['Promo']['SchoolImageSha1'], @parsed_response['Promo'])

    # Step 3
    params = { 'promo_id' => promo['Id'] }

    new_image_id = upload_image(@user.oauth_token, generate_random_image, params)
    assert(new_image_id)

    # Step 4
    params = { 'promo_id' => promo['Id'] }

    get '/pros/lookup', params
    assert_response(@response, :success)
    assert(@parsed_response['Promo'], @parsed_response)
    assert_equal(new_image_id, @parsed_response['Promo']['SchoolImageSha1'], @parsed_response['Promo'])

    # Step 5
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => promo['Id'],
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert(@parsed_response['promo'], @parsed_response)
    assert_equal(new_image_id, @parsed_response['promo']['school_image_sha1'], @parsed_response['promo'])
  end

  ##
  # AS-7173 | YP4S - Maintain active promos for a user (SRP & MIP)
  #
  # Steps:
  # Setup: Create Promo & User
  # 1. Verify response for promo_id and user_in_promo options for /cons/search
  # 2. Verify response for promo_id and user_in_promo options for /cons/business
  def test_user_with_multiple_promos_active_promo_srp_mip
    # Setup
    @user = setup_user

    my_teams = @promo['TeamNames'].shuffle!

    promo_params = { 'start_date' => (Time.now - 1.day).to_i }

    create_new_promo(promo_params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo']['Id'])
    refute_empty(@parsed_response['Promo']['TeamNames'])
    promo_2 = @parsed_response['Promo']
    my_teams_2 = promo_2['TeamNames'].shuffle!

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    user_params = {
        'promo_id' => @active_promo_id,
        'my_teams' => my_teams[0, 1]
    }

    user_params['promo_team'] = my_teams

    put '/usr', user_params, headers
    assert_response(@response, :success)
    assert(my_teams.include?(@parsed_response['promo_team']), @parsed_response['promo_teams'])
    assert(@parsed_response['promo_teams'].include?(my_teams[0]), @parsed_response['promo_teams'])
    assert(@parsed_response['promo_teams'].include?(my_teams[1]), @parsed_response['promo_teams'])

    user_params = {
        'promo_id' => promo_2['Id'],
        'promo_team' => my_teams_2[0]
    }

    put '/usr', user_params, headers
    assert_response(@response, :success)
    assert(my_teams_2.include?(@parsed_response['promo_team']), @parsed_response['promo_teams'])
    assert(@parsed_response['promo_teams'].include?(my_teams_2[0]), @parsed_response['promo_teams'])

    # Step 1
    search_params = {
        'oauth_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
    }

    int_xxids = []
    get_consumer_search_resp('restaurants', 'los angeles, ca', search_params)
    assert_response(@response, :success)
    refute_empty(@parsed_response['SearchResult']['BusinessListings'])
    @parsed_response['SearchResult']['BusinessListings'].each do |listing|
      assert(listing['Promo'],
             "Missing Promo key for SRP Response: restaurants, los angeles ca, #{search_params}")
      int_xxids << listing['Int_Xxid']
    end

    search_params = {
        'oauth_token' => @user.oauth_token,
        'user_in_promo' => true,
    }

    get_consumer_search_resp('restaurants', 'los angeles, ca', search_params)
    assert_response(@response, :success)
    refute_empty(@parsed_response['SearchResult']['BusinessListings'])
    @parsed_response['SearchResult']['BusinessListings'].each do |listing|
      assert(listing['Promo'],
             "Missing Promo key for SRP Response: restaurants, los angeles ca, #{search_params}")
    end

    # Step 2
    assign_http(Config['panda']['host'])

    int_xxid = int_xxids[0]

    search_params = {
        'int_xxid' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
    }

    get '/cons/business', search_params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Business'])
    assert(@parsed_response['Business']['Promo'], @parsed_response['Business'])

    search_params = {
        'int_xxid' => int_xxids[1],
        'oauth_token' => @user.oauth_token,
        'user_in_promo' => true,
    }

    get '/cons/business', search_params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Business'])
    assert(@parsed_response['Business']['Promo'], @parsed_response['Business'])
  end

  ##
  # AS-7384 | YP4S Tool Support - Add a flag to indicate if the promo is paid
  # AS-7355 | YP4S: Tools Support - Ability to add new_listing_points and updated_listing_points
  # ~ PUT /pros
  #
  # Steps:
  # Setup: Create Promo
  # 1. Verify response for updating promo to set is_payable using 1 / 0
  # 2. Verify response for updating promo to set is_payable using true / false
  # 3. Verify response for updating promo to set {new|update}_listing_itl_points
  def test_update_promo_details
    # Setup
    assign_http(Config['panda']['host'])

    promo_params = { 'start_date' => (Time.now - 1.day).to_i }

    create_new_promo(promo_params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo']['Id'])
    promo = @parsed_response['Promo']
    refute_empty(promo['TeamNames'])
    assert_equal(0, promo['IsPayable'], @parsed_response)

    # Step 1
    [1, 0].each do |n|
      params = {
          'promo_id' => promo['Id'],
          'is_payable' => n,
      }

      put '/pros', params
      assert_response(@response, :success)
      assert_equal(n, @parsed_response['Promo']['IsPayable'], @parsed_response)

      promo_check = get_promo_with_code(promo['Code'])
      assert_equal(n, promo_check['IsPayable'], promo_check)
    end

    # Step 2
    [true, false].each do |bool|
      params = {
          'promo_id' => promo['Id'],
          'is_payable' => bool,
      }

      bool ? n = 1 : n = 0

      put '/pros', params
      assert_response(@response, :success)
      assert_equal(n, @parsed_response['Promo']['IsPayable'], @parsed_response)

      promo_check = get_promo_with_code(promo['Code'])
      assert_equal(n, promo_check['IsPayable'], promo_check)
    end

    # Step 3
    new_listing = 25
    update_listing = 15

    2.times do
      params = {
          'promo_id' => promo['Id'],
          'new_listing_itl_points' => new_listing,
          'update_listing_itl_points' => update_listing,
      }

      put '/pros', params
      assert_response(@response, :success)
      assert_equal(new_listing, @parsed_response['Promo']['NewListingItlPoints'], @parsed_response)
      assert_equal(update_listing, @parsed_response['Promo']['UpdateListingItlPoints'], @parsed_response)

      promo_check = get_promo_with_code(promo['Code'])
      assert_equal(new_listing, promo_check['NewListingItlPoints'], promo_check)
      assert_equal(update_listing, promo_check['UpdateListingItlPoints'], promo_check)

      new_listing += rand(10..20)
      update_listing += rand(10..20)
    end
  end

  ##
  # AS-7324 | Endpoint from Panda to Sync ITL status and promo info
  # AS-7388 | ITL- Revisit handling points when status is rejected
  # AS-7418 | YP4S - Subtract rejected ITL points from correct teams
  #
  # Steps:
  # Setup: New user signs up for promo
  # 1. Get the base dashboard & leaderboard stats for user with single team
  #    a) Verify base dashboard stats
  #    b) Verify base leadboard team stats
  # 2. User with Single Team; Approve:
  #    a) User updates listing from promo
  #    b) ITL moderator approves Listing Update
  #    c) Verify the dashboard user and promo stats increase from the approved values
  #    d) Verify the leaderboard team stats increase from the approved values
  # 3. User with Single Team; Approve, Approve, Reject:
  #    a) User updates second listing from promo
  #    b) ITL moderator approves Listing Update
  #    c) Verify the dashboard user and promo stats increase from the approved values
  #    d) Verify the leaderboard team stats increase from the approved values
  #    e) ITL moderator approves the approved Listing Update
  #    f) Verify the dashboard user and promo stats remain the same
  #    g) Verify the leaderboard team stats remain the same
  #    h) ITL moderator rejects the approved Listing Update
  #    i) Verify the dashboard user and promo stats return to the base values
  #    j) Verify the leaderboard team stats return to the base values
  # 4. User with Single Team; Reject, Reject, Approve:
  #    a) User updates second listing from promo
  #    b) ITL moderator rejects Listing Update
  #    c) Verify the dashboard user and promo stats return to the base values
  #    d) Verify the leaderboard team stats increase from the approved values
  #    e) ITL moderator rejcts the rejected Listing Update
  #    f) Verify the dashboard user and promo stats remain the same
  #    g) Verify the leaderboard team stats remain the same
  #    h) ITL moderator approves the rejected Listing Update
  #    i) Verify the dashboard user and promo stats increase from the approved values
  #    j) Verify the leaderboard team stats return to the base values
  # 5. User with Multiple Teams; Approve, Reject:
  #    a) User adds second team
  #    b) Verify base leaderboard team & team 2 stats
  #    c) User updates fourth listing from promo
  #    d) ITL moderator approves Listing Update
  #    e) Verify the dashboard user and promo stats increase from the approved values
  #    f) Verify the leaderboard team stats increase from the approved values
  #    g) ITL moderator rejects the approved Listing Update
  #    h) Verify the dashboard user and promo stats return to the base values
  #    i) Verify the leaderboard team stats return to the base values
  # 6. User with Multiple Teams; Approve, Reject:
  #    a) User updates fourth listing from promo
  #    b) User adds third team
  #    c) Verify base leaderboard team, team 2, & team 3 stats
  #    d) ITL moderator approves Listing Update
  #    e) Verify the dashboard user and promo stats increase from the approved values
  #    f) Verify the leaderboard team stats increase from the approved values
  #    g) ITL moderator rejects the approved Listing Update
  #    h) Verify the dashboard user and promo stats return to the base values
  #    i) Verify the leaderboard team stats return to the base values
  def test_recalculation_for_rejecting_itl_updates_from_promo
    # Setup
    @user = setup_user

    update_itl_points = @promo['UpdateListingItlPoints']
    my_teams = [@promo['TeamNames'].pop]

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_teams'] = my_teams

    put '/usr', params, headers
    assert_response(@response, :success)

    listings = get_promo_listings.shuffle
    assert(listings.length >= 5)

    # Step 1 (a)
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    promo = @parsed_response['promo']
    assert_equal(@active_promo_id, promo['id'])
    assert(@parsed_response['user_stats'])
    assert_equal(0, @parsed_response['user_stats']['contributed_points'])

    # Step 1 (b)
    params = {
        'promo_id' => @active_promo_id,
        'access_token' => @user.oauth_token,
        'api_key' => @api_key
    }

    get '/pros/leaderboard', params
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    assert_equal(@active_promo_id , @parsed_response['promo']['id'])
    refute_empty(@parsed_response['leaderboard'])
    team_stats = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[0] }
    refute_nil(team_stats, @parsed_response['leaderboard'])
    assert(team_stats['contributed_points'])

    # Step 2 (a)
    assign_http(Config['panda']['host'])

    params = {
        'listing_improvement' => {
            'user_id' => @user.id,
            'promo_id' => @active_promo_id,
            'int_xxid' => "#{listings[0]['Int_Xxid']}",
            'zip' => '12345'
        }.to_json   # '/listing_improvement' requires this as json
    }

    post '/listing_improvement', params
    assert_response(@response, :success)
    assert(@parsed_response['id'],
           "Expected id to be returned with listing improvement response: #{@parsed_response}")
    itl_ids = [@parsed_response['id']]
    assert_equal("#{listings[0]['Int_Xxid']}".to_i, @parsed_response['int_xxid'])
    assert_equal(@user.id, @parsed_response['user_id'])
    assert_equal(@active_promo_id, @parsed_response['promo_id'])
    assert_equal('12345', @parsed_response['zip'])
    assert_equal(update_itl_points, @parsed_response['points'])
    assert_nil(@parsed_response['status'],
               "Expected Status to be nil for initial itl update: #{@parsed_response['status']}")
    refute_nil(@parsed_response['promo_user_team_ids'], @parsed_response) unless ENV['test_env'] == 'stage' # AS 5.0 ~ AS-7418

    # Step 2 (b)
    params = {
        'promo_id' => @active_promo_id,
        'listing_improvement_ids' => itl_ids,
        'status' => 'manual_approved'
    }

    put '/pros/itl', params
    assert_response(@response, :success)

    # Step 2 (c)
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert(@parsed_response['user_stats'])
    assert_equal(update_itl_points, @parsed_response['user_stats']['contributed_points'],
                 "Expected user contributed points #{update_itl_points} to equal: #{@parsed_response['user_stats']['contributed_points']}")
    assert_equal((promo['contributed_points'] + update_itl_points), @parsed_response['promo']['contributed_points'],
                 "Expected promo contributed points #{(promo['contributed_points'] + update_itl_points)} to equal: #{@parsed_response['promo']['contributed_points']}")

    user_stats = @parsed_response['user_stats'].dup
    promo = @parsed_response['promo'].dup

    # Step 2 (d)
    get '/pros/leaderboard', params
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    assert_equal(@active_promo_id , @parsed_response['promo']['id'])
    refute_empty(@parsed_response['leaderboard'])
    team_check = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[0] }
    assert_equal((team_stats['contributed_points'] + update_itl_points), team_check['contributed_points'],
                 "Expected team contributed points #{(team_stats['contributed_points'] + update_itl_points)} to equal: #{team_check['contributed_points']}")

    team_stats = team_check
    user_stats_check = nil
    promo_check = nil

    # Step 3 (a)
    assign_http(Config['panda']['host'])

    params = {
        'listing_improvement' => {
            'user_id' => @user.id,
            'promo_id' => @active_promo_id,
            'int_xxid' => "#{listings[1]['Int_Xxid']}",
            'zip' => '23456'
        }.to_json   # '/listing_improvement' requires this as json
    }

    post '/listing_improvement', params
    assert_response(@response, :success)
    assert(@parsed_response['id'],
           "Expected id to be returned with listing improvement response: #{@parsed_response}")
    itl_ids = [@parsed_response['id']]
    assert_equal("#{listings[1]['Int_Xxid']}".to_i, @parsed_response['int_xxid'])
    assert_equal(@user.id, @parsed_response['user_id'])
    assert_equal(@active_promo_id, @parsed_response['promo_id'])
    assert_equal('23456', @parsed_response['zip'])
    assert_equal(update_itl_points, @parsed_response['points'])
    assert_nil(@parsed_response['status'],
               "Expected Status to be nil for initial itl update: #{@parsed_response['status']}")
    refute_nil(@parsed_response['promo_user_team_ids'], @parsed_response) unless ENV['test_env'] == 'stage' # AS 5.0 ~ AS-7418

    # Step 3 (b,e,h)
    ['approved', 'rejected', 'manual_rejected'].each do |status|
      assign_http(Config['panda']['host'])

      params = {
          'promo_id' => @active_promo_id,
          'listing_improvement_ids' => itl_ids,
          'status' => status
      }

      put '/pros/itl', params
      assert_response(@response, :success)

      # Step 3 (c,f,i)
      assign_http(Config['snake']['host'])

      params = {
          'access_token' => @user.oauth_token,
          'promo_id' => @active_promo_id,
          'api_key' => @api_key
      }

      get '/pros/dashboard', params
      assert_response(@response, :success)
      assert(@parsed_response['promo'])
      assert_equal(@active_promo_id, @parsed_response['promo']['id'])
      assert(@parsed_response['user_stats'])
      if status == 'approved'
        assert_equal((user_stats['contributed_points'] + update_itl_points), @parsed_response['user_stats']['contributed_points'],
                     "Expected user contributed points #{(user_stats['contributed_points'] + update_itl_points)} to equal: #{@parsed_response['user_stats']['contributed_points']}")
        assert_equal((promo['contributed_points'] + update_itl_points), @parsed_response['promo']['contributed_points'],
                     "Expected promo contributed points #{(promo['contributed_points'] + update_itl_points)} to equal: #{@parsed_response['promo']['contributed_points']}")
      else
        assert_equal(user_stats['contributed_points'], @parsed_response['user_stats']['contributed_points'],
                     "Expected user contributed points #{user_stats['contributed_points']} to equal: #{@parsed_response['user_stats']['contributed_points']}")
        assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'],
                     "Expected promo contributed points #{promo['contributed_points']} to equal: #{@parsed_response['promo']['contributed_points']}")
      end

      user_stats_check = @parsed_response['user_stats'].dup
      promo_check = @parsed_response['promo'].dup

      # Step 3 (d,g,j)
      get '/pros/leaderboard', params
      assert_response(@response, :success)
      assert(@parsed_response['promo'])
      assert_equal(@active_promo_id , @parsed_response['promo']['id'])
      refute_empty(@parsed_response['leaderboard'])
      team_check = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[0] }
      refute_nil(team_check, @parsed_response['leaderboard'])
      if status == 'approved'
        assert_equal((team_stats['contributed_points'] + update_itl_points), team_check['contributed_points'],
                     "Expected team contributed points #{(team_stats['contributed_points'] + update_itl_points)} to equal: #{team_check['contributed_points']}")
      else
        assert_equal(team_stats['contributed_points'], team_check['contributed_points'],
                     "Expected team contributed points #{team_stats['contributed_points']} to equal: #{team_check['contributed_points']}")
      end
    end

    user_stats = user_stats_check
    promo = promo_check
    team_stats = team_check

    # Step 4 (a)
    assign_http(Config['panda']['host'])

    params = {
        'listing_improvement' => {
            'user_id' => @user.id,
            'promo_id' => @active_promo_id,
            'int_xxid' => "#{listings[2]['Int_Xxid']}",
            'zip' => '34567'
        }.to_json   # '/listing_improvement' requires this as json
    }

    post '/listing_improvement', params
    assert_response(@response, :success)
    assert(@parsed_response['id'],
           "Expected id to be returned with listing improvement response: #{@parsed_response}")
    itl_ids = [@parsed_response['id']]
    assert_equal("#{listings[2]['Int_Xxid']}".to_i, @parsed_response['int_xxid'])
    assert_equal(@user.id, @parsed_response['user_id'])
    assert_equal(@active_promo_id, @parsed_response['promo_id'])
    assert_equal('34567', @parsed_response['zip'])
    assert_equal(update_itl_points, @parsed_response['points'])
    assert_nil(@parsed_response['status'],
               "Expected Status to be nil for initial itl update: #{@parsed_response['status']}")
    refute_nil(@parsed_response['promo_user_team_ids'], @parsed_response) unless ENV['test_env'] == 'stage' # AS 5.0 ~ AS-7418

    # Step 4 (b,e,h)
    ['rejected', 'manual_rejected', 'approved'].each do |status|
      assign_http(Config['panda']['host'])

      params = {
          'promo_id' => @active_promo_id,
          'listing_improvement_ids' => itl_ids,
          'status' => status
      }

      put '/pros/itl', params
      assert_response(@response, :success)

      # Step 4 (c,f,i)
      assign_http(Config['snake']['host'])

      params = {
          'access_token' => @user.oauth_token,
          'promo_id' => @active_promo_id,
          'api_key' => @api_key
      }

      get '/pros/dashboard', params
      assert_response(@response, :success)
      assert(@parsed_response['promo'])
      assert_equal(@active_promo_id, @parsed_response['promo']['id'])
      assert(@parsed_response['user_stats'])
      if status == 'approved'
        assert_equal((user_stats['contributed_points'] + update_itl_points), @parsed_response['user_stats']['contributed_points'],
                     "Expected user contributed points #{(user_stats['contributed_points'] + update_itl_points)} to equal: #{@parsed_response['user_stats']['contributed_points']}")
        assert_equal((promo['contributed_points'] + update_itl_points), @parsed_response['promo']['contributed_points'],
                     "Expected promo contributed points #{(promo['contributed_points'] + update_itl_points)} to equal: #{@parsed_response['promo']['contributed_points']}")
      else
        assert_equal(user_stats['contributed_points'], @parsed_response['user_stats']['contributed_points'],
                     "Expected user contributed points #{user_stats['contributed_points']} to equal: #{@parsed_response['user_stats']['contributed_points']}")
        assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'],
                     "Expected promo contributed points #{promo['contributed_points']} to equal: #{@parsed_response['promo']['contributed_points']}")
      end

      user_stats_check = @parsed_response['user_stats'].dup
      promo_check = @parsed_response['promo'].dup

      # Step 4 (d,g,j)
      get '/pros/leaderboard', params
      assert_response(@response, :success)
      assert(@parsed_response['promo'])
      assert_equal(@active_promo_id , @parsed_response['promo']['id'])
      refute_empty(@parsed_response['leaderboard'])
      team_check = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[0] }
      refute_nil(team_check, @parsed_response['leaderboard'])
      if status == 'approved'
        assert_equal((team_stats['contributed_points'] + update_itl_points), team_check['contributed_points'],
                     "Expected team contributed points #{(team_stats['contributed_points'] + update_itl_points)} to equal: #{team_check['contributed_points']}")
      else
        assert_equal(team_stats['contributed_points'], team_check['contributed_points'],
                     "Expected team contributed points #{team_stats['contributed_points']} to equal: #{team_check['contributed_points']}")
      end
    end

    user_stats = user_stats_check
    promo = promo_check

    # Step 5 (a)
    my_teams.push(@promo['TeamNames'].pop)

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_teams'] = my_teams

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 5 (b)
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/leaderboard', params
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    assert_equal(@active_promo_id , @parsed_response['promo']['id'])
    refute_empty(@parsed_response['leaderboard'])
    team_stats = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[0] }
    team_2_stats = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[1] }
    assert(team_stats, @parsed_response['leaderboard'])
    assert(team_2_stats, @parsed_response['leaderboard'])

    # Step 5 (c)
    assign_http(Config['panda']['host'])

    params = {
        'listing_improvement' => {
            'user_id' => @user.id,
            'promo_id' => @active_promo_id,
            'int_xxid' => "#{listings[3]['Int_Xxid']}",
            'zip' => '34567'
        }.to_json   # '/listing_improvement' requires this as json
    }

    post '/listing_improvement', params
    assert_response(@response, :success)
    assert(@parsed_response['id'],
           "Expected id to be returned with listing improvement response: #{@parsed_response}")
    itl_ids = [@parsed_response['id']]
    assert_equal("#{listings[3]['Int_Xxid']}".to_i, @parsed_response['int_xxid'])
    assert_equal(@user.id, @parsed_response['user_id'])
    assert_equal(@active_promo_id, @parsed_response['promo_id'])
    assert_equal('34567', @parsed_response['zip'])
    assert_equal(update_itl_points, @parsed_response['points'])
    assert_nil(@parsed_response['status'],
               "Expected Status to be nil for initial itl update: #{@parsed_response['status']}")
    refute_nil(@parsed_response['promo_user_team_ids'], @parsed_response) unless ENV['test_env'] == 'stage' # AS 5.0 ~ AS-7418

    # Step 5 (d,g)
    calc_itl_points = ((update_itl_points.fdiv(my_teams.length)).ceil * my_teams.length)
    split_team_points = calc_itl_points.div(my_teams.length)

    ['approved', 'rejected'].each do |status|
      assign_http(Config['panda']['host'])

      params = {
          'promo_id' => @active_promo_id,
          'listing_improvement_ids' => itl_ids,
          'status' => status
      }

      put '/pros/itl', params
      assert_response(@response, :success)

      # Step 5 (e,h)
      assign_http(Config['snake']['host'])

      params = {
          'access_token' => @user.oauth_token,
          'promo_id' => @active_promo_id,
          'api_key' => @api_key
      }

      get '/pros/dashboard', params
      assert_response(@response, :success)
      assert(@parsed_response['promo'])
      assert_equal(@active_promo_id, @parsed_response['promo']['id'])
      assert(@parsed_response['user_stats'])
      if status == 'approved'
        assert_equal((user_stats['contributed_points'] + calc_itl_points), @parsed_response['user_stats']['contributed_points'],
                     "Expected user contributed points #{(user_stats['contributed_points'] + calc_itl_points)} to equal: #{@parsed_response['user_stats']['contributed_points']}")
        assert_equal((promo['contributed_points'] + calc_itl_points), @parsed_response['promo']['contributed_points'],
                     "Expected promo contributed points #{(promo['contributed_points'] + calc_itl_points)} to equal: #{@parsed_response['promo']['contributed_points']}")
      else
        assert_equal(user_stats['contributed_points'], @parsed_response['user_stats']['contributed_points'],
                     "Expected user contributed points #{user_stats['contributed_points']} to equal: #{@parsed_response['user_stats']['contributed_points']}")
        assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'],
                     "Expected promo contributed points #{promo['contributed_points']} to equal: #{@parsed_response['promo']['contributed_points']}")
      end

      # Step 5 (f,i)
      get '/pros/leaderboard', params
      assert_response(@response, :success)
      assert(@parsed_response['promo'])
      assert_equal(@active_promo_id , @parsed_response['promo']['id'])
      refute_empty(@parsed_response['leaderboard'])
      team_check = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[0] }
      team_2_check = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[1] }
      refute_nil(team_check, @parsed_response['leaderboard'])
      refute_nil(team_2_check, @parsed_response['leaderboard'])
      if status == 'approved'
        assert_equal((team_stats['contributed_points'] + split_team_points), team_check['contributed_points'],
                     "Expected team contributed points #{(team_stats['contributed_points'] + split_team_points)} to equal: #{team_check['contributed_points']}")
        assert_equal((team_2_stats['contributed_points'] + split_team_points), team_2_check['contributed_points'],
                     "Expected team contributed points #{(team_2_stats['contributed_points'] + split_team_points)} to equal: #{team_2_check['contributed_points']}")
      else
        assert_equal(team_stats['contributed_points'], team_check['contributed_points'],
                     "Expected team contributed points #{team_stats['contributed_points']} to equal: #{team_check['contributed_points']}")
        assert_equal(team_2_stats['contributed_points'], team_2_check['contributed_points'],
                     "Expected team contributed points #{team_2_stats['contributed_points']} to equal: #{team_2_check['contributed_points']}")
      end
    end

    user_stats = user_stats_check
    promo = promo_check

    # Step 6 (a)
    assign_http(Config['panda']['host'])

    params = {
        'listing_improvement' => {
            'user_id' => @user.id,
            'promo_id' => @active_promo_id,
            'int_xxid' => "#{listings[4]['Int_Xxid']}",
            'zip' => '34567'
        }.to_json   # '/listing_improvement' requires this as json
    }

    post '/listing_improvement', params
    assert_response(@response, :success)
    assert(@parsed_response['id'],
           "Expected id to be returned with listing improvement response: #{@parsed_response}")
    itl_ids = [@parsed_response['id']]
    assert_equal("#{listings[4]['Int_Xxid']}".to_i, @parsed_response['int_xxid'])
    assert_equal(@user.id, @parsed_response['user_id'])
    assert_equal(@active_promo_id, @parsed_response['promo_id'])
    assert_equal('34567', @parsed_response['zip'])
    assert_equal(update_itl_points, @parsed_response['points'])
    assert_nil(@parsed_response['status'],
               "Expected Status to be nil for initial itl update: #{@parsed_response['status']}")
    refute_nil(@parsed_response['promo_user_team_ids'], @parsed_response) unless ENV['test_env'] == 'stage' # AS 5.0 ~ AS-7418

    calc_itl_points = ((update_itl_points.fdiv(my_teams.length)).ceil * my_teams.length)
    split_team_points = calc_itl_points.div(my_teams.length)

    # Step 5 (b)
    my_teams.push(@promo['TeamNames'].pop)

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_teams'] = my_teams

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 6 (c)
    assign_http(Config['snake']['host'])

    params = {
        'access_token' => @user.oauth_token,
        'promo_id' => @active_promo_id,
        'api_key' => @api_key
    }

    get '/pros/leaderboard', params
    assert_response(@response, :success)
    assert(@parsed_response['promo'])
    assert_equal(@active_promo_id , @parsed_response['promo']['id'])
    refute_empty(@parsed_response['leaderboard'])
    team_stats = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[0] }
    team_2_stats = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[1] }
    team_3_stats = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[2] }
    assert(team_stats, @parsed_response['leaderboard'])
    assert(team_2_stats, @parsed_response['leaderboard'])
    assert(team_3_stats, @parsed_response['leaderboard'])

    # Step 6 (d,g)
    ['approved', 'rejected'].each do |status|
      assign_http(Config['panda']['host'])

      params = {
          'promo_id' => @active_promo_id,
          'listing_improvement_ids' => itl_ids,
          'status' => status
      }

      put '/pros/itl', params
      assert_response(@response, :success)

      # Step 6 (e,h)
      assign_http(Config['snake']['host'])

      params = {
          'access_token' => @user.oauth_token,
          'promo_id' => @active_promo_id,
          'api_key' => @api_key
      }

      get '/pros/dashboard', params
      assert_response(@response, :success)
      assert(@parsed_response['promo'])
      assert_equal(@active_promo_id, @parsed_response['promo']['id'])
      assert(@parsed_response['user_stats'])
      if status == 'approved'
        assert_equal((user_stats['contributed_points'] + calc_itl_points), @parsed_response['user_stats']['contributed_points'],
                     "Expected user contributed points #{(user_stats['contributed_points'] + calc_itl_points)} to equal: #{@parsed_response['user_stats']['contributed_points']}")
        assert_equal((promo['contributed_points'] + calc_itl_points), @parsed_response['promo']['contributed_points'],
                     "Expected promo contributed points #{(promo['contributed_points'] + calc_itl_points)} to equal: #{@parsed_response['promo']['contributed_points']}")
      else
        assert_equal(user_stats['contributed_points'], @parsed_response['user_stats']['contributed_points'],
                     "Expected user contributed points #{user_stats['contributed_points']} to equal: #{@parsed_response['user_stats']['contributed_points']}")
        assert_equal(promo['contributed_points'], @parsed_response['promo']['contributed_points'],
                     "Expected promo contributed points #{promo['contributed_points']} to equal: #{@parsed_response['promo']['contributed_points']}")
      end

      # Step 6 (f,i)
      get '/pros/leaderboard', params
      assert_response(@response, :success)
      assert(@parsed_response['promo'])
      assert_equal(@active_promo_id , @parsed_response['promo']['id'])
      refute_empty(@parsed_response['leaderboard'])
      team_check = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[0] }
      team_2_check = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[1] }
      team_3_check = @parsed_response['leaderboard'].find { |team| team['name'] == my_teams[2] }
      refute_nil(team_check, @parsed_response['leaderboard'])
      refute_nil(team_2_check, @parsed_response['leaderboard'])
      refute_nil(team_3_check, @parsed_response['leaderboard'])
      if status == 'approved'
        assert_equal((team_stats['contributed_points'] + split_team_points), team_check['contributed_points'],
                     "Expected team contributed points #{(team_stats['contributed_points'] + split_team_points)} to equal: #{team_check['contributed_points']}")
        assert_equal((team_2_stats['contributed_points'] + split_team_points), team_2_check['contributed_points'],
                     "Expected team contributed points #{(team_2_stats['contributed_points'] + split_team_points)} to equal: #{team_2_check['contributed_points']}")
        assert_equal(team_3_stats['contributed_points'], team_3_check['contributed_points'],
                     "Expected team contributed points #{team_3_stats['contributed_points']} to equal: #{team_3_check['contributed_points']}")
      else
        assert_equal(team_stats['contributed_points'], team_check['contributed_points'],
                     "Expected team contributed points #{team_stats['contributed_points']} to equal: #{team_check['contributed_points']}")
        assert_equal(team_2_stats['contributed_points'], team_2_check['contributed_points'],
                     "Expected team contributed points #{team_2_stats['contributed_points']} to equal: #{team_2_check['contributed_points']}")
        assert_equal(team_3_stats['contributed_points'], team_3_check['contributed_points'],
                     "Expected team contributed points #{team_3_stats['contributed_points']} to equal: #{team_3_check['contributed_points']}")
      end
    end
  end

  ##
  # AS-7386 | YP4S: Tools Support - Support start and end date on dashboard
  #
  # Steps
  # Setup
  # 1. Verify GET /pros response with no parameters
  # 2. Verify GET /pros response with custom_start_date & custom_end_date
  # 3. Verify GET /pros response +paid_promos
  # 4. Verify GET /pros response +include_promo_stats
  def test_promos_endpoint_filters
    # Setup
    assign_http(Config['panda']['host'])

    start_date = (Time.new - 30.day).to_i
    end_date = (Time.new - 5.day).to_i

    # Step 1
    get '/pros', {}
    assert_response(@response, :success)
    refute_empty(@parsed_response['Promos'])
    refute(@parsed_response['ToolStats'])
    refute(@parsed_response['PromoStatsMap'])

    # Step 2
    params = {
        'custom_start_date' => start_date,
        'custom_end_date' => end_date,
    }

    get '/pros', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Promos'], @parsed_response)
    assert(@parsed_response['ToolStats'], @parsed_response)
    refute(@parsed_response['PromoStatsMap'], @parsed_response)
    assert(@parsed_response['ToolStats']['CustomStats'], @parsed_response['ToolStats'])
    assert(@parsed_response['ToolStats']['AlltimeStats'], @parsed_response['ToolStats'])
    unless @parsed_response['ToolStats']['CustomStats'].blank?
      @parsed_response['ToolStats']['CustomStats'].each do |cs|
        assert(cs['PromoId'], cs)
        assert(cs['RatingCount'], cs)
        assert(cs['ParticpantsCount'], cs)
      end
    end
    unless @parsed_response['ToolStats']['AlltimeStats'].blank?
      @parsed_response['ToolStats']['AlltimeStats'].each do |ats|
        assert(ats['PromoId'], ats)
        assert(ats['RatingCount'], ats)
        assert(ats['ParticpantsCount'], ats)
      end
    end

    # Step 3
    params['paid_promos'] = true

    get '/pros', params
    assert_response(@response, :success)
    assert(@parsed_response['Promos'], @parsed_response)
    assert(@parsed_response['ToolStats'], @parsed_response)
    refute(@parsed_response['PromoStatsMap'], @parsed_response)
    assert(@parsed_response['ToolStats']['CustomStats'], @parsed_response['ToolStats'])
    assert(@parsed_response['ToolStats']['AlltimeStats'], @parsed_response['ToolStats'])
    unless @parsed_response['Promos'].empty?
      @parsed_response['Promos'].each do |promo|
        assert_equal(1, promo['IsPayable'],
                     "Expected IsPayable to equal 1 for all promos in the response: #{promo}")
        cs_check = @parsed_response['ToolStats']['CustomStats'].find { |cs| cs['PromoId'] == promo['Id'] }
        if cs_check
          assert(promo['ReviewCount'] >= cs_check['RatingCount'],
                 "Expected Promo ReviewCount #{promo['ReviewCount']} to be greater than or equal to CustomStats RatingCount: #{cs_check['RatingCount']}")
          assert(promo['UserCount'] >= cs_check['ParticpantsCount'],
                 "Expected Promo UserCount #{promo['UserCount']} to be greater than or equal to CustomStats ParticpantsCount: #{cs_check['ParticpantsCount']}")
        end
        ats_check = @parsed_response['ToolStats']['AlltimeStats'].find { |ats| ats['PromoId'] == promo['Id'] }
        if ats_check
          assert_equal(promo['ReviewCount'], ats_check['RatingCount'])
          assert_equal(promo['UserCount'], ats_check['ParticpantsCount'])
        end
      end
    end

    # Step 4
    params['include_promo_stats'] = true

    get '/pros', params
    assert_response(@response, :success)
    assert(@parsed_response['Promos'], @parsed_response)
    assert(@parsed_response['ToolStats'], @parsed_response)
    assert(@parsed_response['PromoStatsMap'], @parsed_response)
    assert(@parsed_response['ToolStats']['CustomStats'], @parsed_response['ToolStats'])
    assert(@parsed_response['ToolStats']['AlltimeStats'], @parsed_response['ToolStats'])
    unless @parsed_response['Promos'].empty?
      @parsed_response['Promos'].each do |promo|
        if @parsed_response['PromoStatsMap']["#{promo['Id']}"]
          assert_has_keys(@parsed_response['PromoStatsMap']["#{promo['Id']}"], ['CurrentLevel','NextLevel'])
        end
      end
    end
  end

  ##
  # AS-7390 | YP4S - Cutting down base points of Promo after 4 weeks of promo start time
  #     Several updates have occurred for this story:
  #     now multiplier and its start date are configurable, otherwise nil
  #
  # Steps:
  # 1. Verify response for multiplier & multiplier_start_date are nil on promo creation when not set
  # 2. Verify response for update to multiplier_start_date set, multiplier nil since not provided
  # 3. Verify response for update to multiplier_start_date set and multiplier
  def test_promo_multiplier_start_date
    # Step 1
    assign_http(Config['panda']['host'])

    start_date =  (Time.now - 1.day).to_i

    promo_params = {
        'start_date' => start_date
    }

    create_new_promo(promo_params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo']['Id'])
    promo = @parsed_response['Promo']
    assert_nil(@parsed_response['Promo']['Multiplier'])
    assert_nil(@parsed_response['Promo']['MultiplierStartDate'])

    # Step 2
    custom_multiplier_start_date = (Time.now + rand(7..28).day).to_i

    promo_params = {
        'promo_id' => promo['Id'],
        'start_date' => start_date,
        'multiplier_start_date' => custom_multiplier_start_date
    }

    put '/pros', promo_params
    assert_response(@response, :success)
    assert_equal(promo['Id'], @parsed_response['Promo']['Id'])
    assert_nil(@parsed_response['Promo']['Multiplier'])
    refute_nil(@parsed_response['Promo']['MultiplierStartDate'])
    multiplier_start_date = DateTime.parse(@parsed_response['Promo']['MultiplierStartDate']).to_i
    assert_equal(custom_multiplier_start_date, multiplier_start_date)

    # Step 3
    start_date =  (Time.now + 10.day).to_i
    custom_multiplier_start_date = (start_date + rand(7..28).day).to_i

    promo_params = {
        'promo_id' => promo['Id'],
        'multiplier' => 0.5,
        'multiplier_start_date' => custom_multiplier_start_date
    }

    put '/pros', promo_params
    assert_response(@response, :success)
    assert_equal(promo['Id'], @parsed_response['Promo']['Id'])
    assert_equal(promo_params['multiplier'], @parsed_response['Promo']['Multiplier'])
    refute_nil(@parsed_response['Promo']['MultiplierStartDate'])
    multiplier_start_date = DateTime.parse(@parsed_response['Promo']['MultiplierStartDate']).to_i
    assert_equal(custom_multiplier_start_date, multiplier_start_date)
  end

  ##
  # AS-7298 | YP4S - Referrals
  # AS-7341 | YP4S - Endpoint for returning the referrer user object and referrer promo
  # AS-7364 | YP4S - Add invitee list & count to dashboard.
  #
  # Steps:
  # 1. User 1 signs up for the promo
  # 2. User 1 gets a referral code
  # 3. Looking up referral code via /pros/referral_code on Panda should return the correct promo and user
  # 4. User 2 signs up with user 1's referral code with one team
  # 5. User 3 signs up with user 1's referral code with two teams
  # 6. User 1's dashboard should show users 2 and 3 as referred
  # 7. Get a business for the promo and store its points data.
  # 8. User 2 reviews a business.
  # 9. User 3 uploads an image.
  # 10. Verify points on all three users' dashboard.
  def test_referrals
    # Step 1
    assign_http(Config['turtle']['host'])

    @user1 = setup_user
    my_team = @promo['TeamNames'].sample

    headers = { 'Authorization' => "Bearer #{@user1.oauth_token}" }
    params = {
      'promo_id' => @active_promo_id,
      'promo_team' => my_team
    }
    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 2
    headers = { 'Authorization' => "Bearer #{@user1.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    get '/pros/referral_code', params, headers
    assert_response(@response, :success)
    referral_code = @parsed_response['referral_code']
    assert(referral_code, 'Expected to have a referral_code, but there was none.')

    # Step 3
    assign_http(Config['snake']['host'])

    params = {
      'code' => referral_code
    }.merge(api_key)
    get '/pros/referral_code', params
    assert_response(@response, :success)
    assert_equal(@active_promo_id, @parsed_response['promo']['id'])
    assert_equal(@user1.id, @parsed_response['referrer']['id'])

    # Step 4
    assign_http(Config['turtle']['host'])

    @user2 = setup_user
    my_team = @promo['TeamNames'].sample

    headers = { 'Authorization' => "Bearer #{@user2.oauth_token}" }
    params = {
      'promo_referral_code' => referral_code,
      'promo_team' => my_team
    }
    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 5
    @user3 = setup_user
    my_team = @promo['TeamNames'].sample

    headers = { 'Authorization' => "Bearer #{@user3.oauth_token}" }
    params = {
      'promo_referral_code' => referral_code,
      'promo_teams' => [
        @promo['TeamNames'].first,
        @promo['TeamNames'].last
      ]
    }
    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 6
    assign_http(Config['snake']['host'])

    params = {
      'access_token' => @user1.oauth_token ,
      'promo_id' => @active_promo_id
    }.merge(api_key)
    get '/pros/dashboard', params
    assert_response(@response, :success)
    assert_equal(2, @parsed_response['user_stats']['referred_user_count'])

    expected_referred_user_ids = [@user2.id, @user3.id]
    actual_referred_user_ids = @parsed_response['user_stats']['referred_users'].map {|user| user['id']}
    assert_equal(expected_referred_user_ids.sort, actual_referred_user_ids.sort)

    # Step 7
    business_listings = get_promo_listings
    int_xxid = business_listings.sample['Int_Xxid']

    search_opts = { 'promo_id' => @active_promo_id }

    get_consumer_business_resp(int_xxid, search_opts)
    assert_response(@response, :success)

    review_points = @parsed_response['Business']['Promo']['ReviewPoints']
    photo_points = @parsed_response['Business']['Promo']['PhotoPoints']

    # Step 8
    params = {
        'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
        'source' => 'XX3',
        'subject' => 'Review made by API',
        'value' => rand(1..5),
        'listing_id' => int_xxid,
        'oauth_token' => @user2.oauth_token,
        'promo_id' => @active_promo_id
    }.merge(api_key)

    put '/snake/usr/reviews', params
    assert_response(@response, :success)

    # Step 9
    upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid, @user3, @active_promo_id)
    assert_response(@response, :success)

    # Step 10
    params = {
      'access_token' => @user1.oauth_token,
      'promo_id' => @active_promo_id
    }.merge(api_key)
    get '/pros/dashboard', params
    assert_response(@response, :success)

    expected_referral_points = (review_points / 10.0).ceil + (photo_points / 10.0).ceil
    assert_equal(expected_referral_points, @parsed_response['user_stats']['contributed_points'])

    params = {
      'access_token' => @user2.oauth_token,
      'promo_id' => @active_promo_id
    }.merge(api_key)
    get '/pros/dashboard', params
    assert_response(@response, :success)

    assert_equal(review_points, @parsed_response['user_stats']['contributed_points'])

    params = {
      'access_token' => @user3.oauth_token,
      'promo_id' => @active_promo_id
    }.merge(api_key)
    get '/pros/dashboard', params
    assert_response(@response, :success)

    photo_points_after_teams = (photo_points / 2.0).ceil * 2
    assert_equal(photo_points_after_teams, @parsed_response['user_stats']['contributed_points'])
  end

  ##
  # AS-7399 - Modify the point calculation to choose base points, addon points, and multiplier separately
  # AS-7512 | YP4S: Fix addon/multiplier for multiple heading_codes/ubercats.
  #
  # Int_Xxid 1505184 has base points set at heading code level, addon points set at uber cat level, and
  # multiplier set at category type level. These should interact with the new implementation of points.
  #
  # Heading code: 8010014
  # Uber cat: Pets
  # Category type: Discovery
  #
  # Steps:
  # Setup: Get random int_xxid, and points for that business
  # 1. Look up random listing for specified params, check review points are calculated correctly:
  #    (base_points * multiplier) + addon_points
  def test_new_points_calculation
    # Setup
    assign_http(Config['panda']['host'])

    heading_code = '8010014'
    uber_cat = 'Pets'
    cat_type = 'Discovery'

    get_consumer_search_resp(uber_cat, 'los angeles, ca')
    assert_response(@response, :success)
    refute_empty(@parsed_response['SearchResult']['BusinessListings'])

    businesses = []
    @parsed_response['SearchResult']['BusinessListings'].each do |business|
      promo_uber_cats = business['PromoUbercats'].split('|') rescue []
      if business['AllHeadingCodes'].include?(heading_code) &&
         promo_uber_cats.include?(uber_cat) &&
         business['CategoryType'] == cat_type &&
         business['Rateable'] == 1
        businesses << business
      end
    end
    refute_empty(businesses)
    int_xxid = businesses.sample['Int_Xxid']
    points = get_promo_points_for_business(int_xxid)
    review = points['details']['review']

    # Step 1
    get_consumer_business_resp(int_xxid, 'promo_id' => @active_promo_id)
    assert_response(@response, :success)
    assert(@parsed_response['Business']['Promo'], @parsed_response)
    actual_points = @parsed_response['Business']['Promo']['ReviewPoints']
    expected_points = ((review['base_points'] * review['multiplier']) + review['addon_points']).ceil
    expected_points += @promo['FirstReviewBonusPoints'] if review['first_review_bonus']
    assert_equal(expected_points, actual_points,
                 "Expected review points for int_xxid: #{int_xxid} to match: " \
                 "base: #{review['base_points']} * multiplier: #{review['multiplier']}, + addon: #{review['addon_points']} points " \
                 "for heading code: #{heading_code}, category type: #{cat_type}, ubercat: #{uber_cat}")
  end

  ##
  # AS-7461 | YP4S - Completeness meter
  # AS-7509 | YP4S - Use user/profile endpoint and app_id = mob to mark the mobile app task as complete
  #
  # Steps
  # Setup: New user and promo team selected
  # 1. Check defaults on new user without promo for completed task fields
  # 2. Check for updates to completed task fields for user that joining a promo
  # 3. Check for updates to completed task fields for request user profile with 'app_id' => 'MOB'
  # 4. Check for updates to completed task fields for user that writes a review
  # 5. Check for updates to completed task fields for user that refer another user to promo
  # 6. Check for updates to completed task fields for user that adds profile photo
  def test_completeness_meter
    # Setup
    @user = setup_user
    teams = @promo['TeamNames'].dup.shuffle
    my_teams = teams.pop

    # Step 1
    get_user_info(@user.oauth_token)
    assert_nil(@parsed_response['active_promo_id'], @parsed_response)
    assert_equal(false, @parsed_response['all_tasks_completed'], @parsed_response)
    assert_empty(@parsed_response['completed_tasks'], @parsed_response)

    assign_http(Config['panda']['host'])

    params = {
        'oauth_token' => @user.oauth_token
    }

    get '/usr/profile_completeness', params
    assert_response(@response, :success)
    @parsed_response['Tasks'].each do |task|
        assert_equal(false, task['Completed'],
                     "Expected all options to be false task: #{task['Id']}")
    end

    # Step 2 ~ join_community
    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    params = {
        'promo_id' => @active_promo_id,
        'promo_team' => my_teams
    }

    put '/usr', params, headers
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['verified'], @parsed_response)
    assert_equal(@active_promo_id, @parsed_response['active_promo_id'], @parsed_response)
    assert_equal(my_teams, @parsed_response['promo_team'], @parsed_response)
    assert(@parsed_response['promo_teams'].include?(my_teams), @parsed_response)

    get_user_info(@user.oauth_token)
    assert_equal(@active_promo_id, @parsed_response['active_promo_id'], @parsed_response)
    assert_equal(false, @parsed_response['all_tasks_completed'], @parsed_response)
    refute_empty(@parsed_response['completed_tasks'], @parsed_response)
    completed_options = @parsed_response['completed_tasks']
    assert(completed_options.include?('join_community'), completed_options)

    assign_http(Config['panda']['host'])

    params = {
        'oauth_token' => @user.oauth_token
    }

    get '/usr/profile_completeness', params
    assert_response(@response, :success)
    @parsed_response['Tasks'].each do |task|
      if completed_options.include?(task['Id'])
        assert_equal(true, task['Completed'],
                     "Expected completed options #{completed_options} to include task: #{task['Id']}")
      else
        assert_equal(false, task['Completed'],
                     "Expected completed options #{completed_options} to not include task: #{task['Id']}")
      end
    end

    # Step 3 ~ mobile_app
    params = {
        'include_promos' => true,
        'include_user_attributes' => true,
        'app_id' => 'MOB',
        'oauth_token' => @user.oauth_token
    }

    get '/usr/profile', params
    assert_response(@response, :success)

    get_user_info(@user.oauth_token)
    assert_equal(@active_promo_id, @parsed_response['active_promo_id'], @parsed_response)
    assert_equal(false, @parsed_response['all_tasks_completed'], @parsed_response)
    refute_empty(@parsed_response['completed_tasks'], @parsed_response)
    completed_options = @parsed_response['completed_tasks']
    assert(completed_options.include?('mobile_app'), completed_options)
    completed_options.each do |co|
      assert(@parsed_response['completed_tasks'].include?(co), @parsed_response)
    end

    assign_http(Config['panda']['host'])

    params = {
        'oauth_token' => @user.oauth_token
    }

    get '/usr/profile_completeness', params
    assert_response(@response, :success)
    @parsed_response['Tasks'].each do |task|
      if completed_options.include?(task['Id'])
        assert_equal(true, task['Completed'],
                     "Expected completed options #{completed_options} to include task: #{task['Id']}")
      else
        assert_equal(false, task['Completed'],
                     "Expected completed options #{completed_options} to not include task: #{task['Id']}")
      end
    end

    # Step 4 ~ write_review
    listings = get_promo_listings(get_promo_heading, 'Los Angeles, CA', 'promo_id' => @active_promo_id)
    int_xxid = listings.sample['Int_Xxid']

    params = {
        'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
        'source' => 'XX3',
        'subject' => 'Review made by API',
        'value' => rand(1..5),
        'listing_id' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'promo_id' => @active_promo_id
    }

    put '/usr/reviews', params
    assert_response(@response, :success)

    get_user_info(@user.oauth_token)
    assert_equal(@active_promo_id, @parsed_response['active_promo_id'], @parsed_response)
    assert_equal(false, @parsed_response['all_tasks_completed'], @parsed_response)
    refute_empty(@parsed_response['completed_tasks'], @parsed_response)
    completed_options = @parsed_response['completed_tasks']
    assert(completed_options.include?('write_review'), completed_options)
    completed_options.each do |co|
      assert(@parsed_response['completed_tasks'].include?(co), @parsed_response)
    end

    assign_http(Config['panda']['host'])

    params = {
        'oauth_token' => @user.oauth_token
    }

    get '/usr/profile_completeness', params
    assert_response(@response, :success)
    @parsed_response['Tasks'].each do |task|
      if completed_options.include?(task['Id'])
        assert_equal(true, task['Completed'],
                     "Expected completed options #{completed_options} to include task: #{task['Id']}")
      else
        assert_equal(false, task['Completed'],
                     "Expected completed options #{completed_options} to not include task: #{task['Id']}")
      end
    end

    # Step 5 ~ invite_others
    @user2 = setup_user

    assign_http(Config['turtle']['host'])

    headers = {
        'Authorization' => "Bearer #{@user.oauth_token}"
    }

    params = {
        'promo_id' => @active_promo_id
    }

    get '/pros/referral_code', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['referral_code'], @parsed_response)
    referral_code = @parsed_response['referral_code']

    headers = {
        'Authorization' => "Bearer #{@user2.oauth_token}"
    }

    params = {
        'promo_referral_code' => referral_code,
        'promo_team' => @promo['TeamNames'].sample
    }

    put '/usr', params, headers
    assert_response(@response, :success)

    get_user_info(@user.oauth_token)
    assert_equal(@active_promo_id, @parsed_response['active_promo_id'], @parsed_response)
    assert_equal(false, @parsed_response['all_tasks_completed'], @parsed_response)
    refute_empty(@parsed_response['completed_tasks'], @parsed_response)
    completed_options = @parsed_response['completed_tasks']
    assert(completed_options.include?('invite_others'), completed_options)
    completed_options.each do |co|
      assert(@parsed_response['completed_tasks'].include?(co), @parsed_response)
    end

    assign_http(Config['panda']['host'])

    params = {
        'oauth_token' => @user.oauth_token
    }

    get '/usr/profile_completeness', params
    assert_response(@response, :success)
    @parsed_response['Tasks'].each do |task|
      if completed_options.include?(task['Id'])
        assert_equal(true, task['Completed'],
                     "Expected completed options #{completed_options} to include task: #{task['Id']}")
      else
        assert_equal(false, task['Completed'],
                     "Expected completed options #{completed_options} to not include task: #{task['Id']}")
      end
    end

    # Step 6 ~ profile_photo
    upload_and_link_image_by_user_id(@user)
    assert_response(@response, :success)

    get_user_info(@user.oauth_token)
    assert_equal(@active_promo_id, @parsed_response['active_promo_id'], @parsed_response)
    assert_equal(true, @parsed_response['all_tasks_completed'], @parsed_response)
    refute_empty(@parsed_response['completed_tasks'], @parsed_response)
    completed_options = @parsed_response['completed_tasks']
    assert(completed_options.include?('profile_photo'), completed_options)
    completed_options.each do |co|
      assert(@parsed_response['completed_tasks'].include?(co), @parsed_response)
    end

    assign_http(Config['panda']['host'])

    params = {
        'oauth_token' => @user.oauth_token
    }

    get '/usr/profile_completeness', params
    assert_response(@response, :success)
    @parsed_response['Tasks'].each do |task|
      assert_equal(true, task['Completed'],
                   "Expected completed options #{completed_options} to include task: #{task['Id']}")
    end
  end

  private

  def api_key
    {
      'api_key' => @api_key
    }
  end
end
