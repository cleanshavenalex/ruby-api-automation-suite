require './init'

class TestPandaRatingsAndResponses < APITest

  # default: 452316899 'All in one movers ohio' attached to 'user_id 501005698'
  OWNER = {
      int_xxid: 452316899,
      uuid: 501005698
  }

  def setup
    assign_http(Config["panda"]["host"])
    @user = setup_user
  end

  ##
  # AS-5409  | Test Customer Ratings
  #
  # Setup: Get Business
  # Test Steps:
  # 1. Error Check: Attempt to Delete Non-Existent Rating
  # 2. Error Check: Attempt to Update Non-Existent Rating
  # 3. Success Check: User Posts Rating to Business Listing
  # 4. Success Check: Panda Receives Second Post to Add Over Existent Rating
  # 5. Success Check: Update Body to Existing Rating
  # 6. Success Check: Update Value to Existing Rating
  # 7. Success Check: Update Subject to Existing Rating
  # 8. Success Check: Delete Existing Rating
  # 9. Success Check: User Posts 2 New Ratings to Business Listing
  # 10. Success Check: Paginating ratings through /cons/business should work properly
  # Cleanup: Remove Ratings from Listing
  def test_customer_ratings
    # Setup
    opts =  {
        'vrid' => @user.vrid,
        'app_id' => 'WEB',
        'ptid' => 'API'
    }

    sr_check = nil
    start_time = Time.now

    while sr_check.nil? && Time.now - start_time < 10
      get_consumer_search_resp('pizza', 'los angeles, ca', opts)
      assert_response(@response, :success)
      sr_check = @parsed_response['SearchResult']['BusinessListings'].first
    end

    businesses = []
    @parsed_response['SearchResult']['BusinessListings'].each do |business|
      if business['Rateable'] == 1
        businesses << business
      end
    end

    refute_empty(businesses, 'No Rateable businesses returned.')
    business = businesses.sample
    int_xxid = business['Int_Xxid']
    name = business['Name']

    get_consumer_business_resp(int_xxid)
    assert_response(@response, :success)
    business = @parsed_response['Business']

    # Step 1
    delete '/rats/6057dee3-ef85-4c98-ABCD-557fd5c49121', {}
    assert_response(@response, 404)

    # Step 2
    params = {
      'rating' => {
        'body' => 'INVALID ID, UPDATE REQUEST SHOULD FAIL!'
      }
    }

    put '/rats/6057dee3-ef85-4c98-ABCD-557fd5c49121', params
    assert_response(@response, 404)

    # Step 3
    params = {
        'int_xxid' => int_xxid,
        'h' => 1000
    }

    get '/rats/business', params
    assert_response(@response, :success)

    params = {
      'body' => "INITIAL USER POST: #{name}, really good Pizza in LA.",
      'source' => 'CSE',
      'subject' => "#{name} is teh good!",
      'value' => 3,
      'int_xxid' => int_xxid,
      'oauth_token' => @user.oauth_token
    }

    post '/rats/add_rating', params
    assert_response(@response, :success)
    assert(@parsed_response['RatingID'], @parsed_response)

    rating_id = @parsed_response['RatingID']

    params = {
      'body' => "POST OVER POST: #{name} this pizza is gross, do not eat here.",
      'source' => 'CSE',
      'subject' => "#{name} is terrible, do not go here!",
      'value' => 1,
      'int_xxid' => int_xxid,
      'oauth_token' => @user.oauth_token
    }

    # Step 4
    post '/rats/add_rating', params
    assert_response(@response, :success)

    # Step 5
    params = {
      'rating' => {
        'body' => "USER UPDATE POST, BODY:  WOW, #{name} is the best" \
          " Pizza in LA! Delicious crust, fresh toppings, just the way I like my pizza"
      }
    }

    put "/rats/#{rating_id}", params
    assert_response(@response, :success)

    # Step 6
    params = {
      'rating' => {
        'value' => 4
      }
    }

    put "/rats/#{rating_id}", params
    assert_response(@response, :success)

    # Step 7
    params = {
      'rating' => {
        'subject' => "#{business['Name']}, truly the Best!!!"
      }
    }

    put "/rats/#{rating_id}", params
    assert_response(@response, :success)

    # Step 8
    delete "/rats/#{rating_id}", {}
    assert_response(@response, :success)

    # Step 9
    params = {
      'body' => "User Rating Message: #{name} ... BEST. PIZZA. IN. LA!",
      'source' => 'CSE',
      'subject' => "#{name}. THE. BEST!",
      'value' => 5,
      'int_xxid' => int_xxid,
      'oauth_token' => @user.oauth_token
    }

    post '/rats/add_rating', params
    assert_response(@response, :success)
    assert(@parsed_response['RatingID'], @parsed_response)

    rating_id1 = @parsed_response['RatingID']

    # Wait 1 second so that there's no chance that the timestamp will be the same in the
    # database, so that sorting by created at will not have a tie
    sleep(1)

    second_user = setup_user

    params = {
      'body' => "User Rating Message: #{name} This is supposed to be a sushi place though.",
      'source' => 'CSE',
      'subject' => "#{name}. THE. BEST!",
      'value' => 1,
      'int_xxid' => int_xxid,
      'oauth_token' => second_user.oauth_token
    }

    post '/rats/add_rating', params
    assert_response(@response, :success)

    rating_id2 = @parsed_response['RatingID']

    # Step 10
    params = {
      'int_xxid' => int_xxid,
      'ratings' => {
        'h' => 1,
        'o' => 0
      }
    }

    get '/cons/business', params
    assert_response(@response, :success)
    assert(@parsed_response['Business']['Ratings'], @parsed_response)
    ratings = @parsed_response['Business']['Ratings']

    assert_equal(1, ratings.count)
    first_paginated_rating = ratings.first['Id']

    params['ratings']['o'] = 1

    get '/cons/business', params
    assert_response(@response, :success)
    assert(@parsed_response['Business']['Ratings'], @parsed_response)
    ratings = @parsed_response['Business']['Ratings']

    assert_equal(1, ratings.count)
    refute_equal(first_paginated_rating, ratings.first['Id'])

    # Cleanup (will only execute if test passes)
    delete "/rats/#{rating_id1}", {}
    assert_response(@response, :success)

    delete "/rats/#{rating_id2}", {}
    assert_response(@response, :success)

    params = {
        'int_xxid' => int_xxid,
        'h' => 1000
    }

    get '/rats/business', params
    assert_response(@response, :success)
    assert(@parsed_response['Ratings'].none? { |x| x['Id'] == rating_id })
  end

  ##
  # AS-5342 | Test Ratings Responses
  #
  # Setup: Get Business
  # Test Steps:
  # 1. User Posts Rating to Business Listing
  # 2. Error Check: Attempt to Delete Non-Existent Response
  # 3. Error Check: Attempt to Update Non-Existent Response
  # 4. Success Check: Add New Response to Current User Post
  # 5. Error Check: Attempt to Add Over Existent Response
  # 6. Success Check: Update Existing Response
  # 7. Success Check: Update Existing to Previously Updated Response
  # 8. Success Check: Delete Existing Response
  # 9. Success Check: Add New Response to Recently Deleted Response
  # Cleanup: Remove Owner Rating Response & User Rating from Listing
  def test_ratings_responses
    # Setup
    business = get_consumer_business_resp(OWNER[:int_xxid])

    # Step 1
    params = {
        'int_xxid' => OWNER[:int_xxid],
        'h' => 1000
    }

    get '/rats/business', params
    assert_response(@response, :success)

    params = {
        'body' => "User Rating Message: #{business['Name']} is the best ever! - UID: #{@user.id}",
        'source' => 'CSE',
        'subject' => "#{business['Name']} Rocks!!!",
        'value' => 4,
        'int_xxid' => OWNER[:int_xxid],
        'oauth_token' => @user.oauth_token
    }

    post '/rats/add_rating', params
    assert_response(@response, :success)

    rating_id = @parsed_response['RatingID'] # Needed for Response Checks & Cleanup

    # Step 2
    params = { 'rating_id' => 'ABC-01234-56789' }

    delete '/rats/rating_response', params
    assert_response(@response, 404)

    # Step 3
    params = {
        'rating_id' => 'ABC-01234-56789',
        'unified_users_id' => OWNER[:uuid],
        'body' => 'Attempted Update to Non-Existing Rating (E)',
        'verified_business_owner' => true
    }

    put '/rats/rating_response', params
    assert_response(@response, 404)

    # Step 4
    params = {
        'rating_id' => rating_id,
        'unified_users_id' => OWNER[:uuid],
        'body' => "INITIAL POST: Thank you very much #{@user.id}, hope you come back soon!",
        'verified_business_owner' => true
    }

    post '/rats/rating_response', params
    assert_response(@response, :success)

    # Step 5
    params = {
        'rating_id' => rating_id,
        'unified_users_id' => OWNER[:uuid],
        'body' => "POST OVER POST (E): Thank you AGAIN #{@user.id}, hope you come back REAL soon!",
        'verified_business_owner' => true
    }

    post '/rats/rating_response', params
    assert_response(@response, 409)

    # Step 6
    params = {
        'rating_id' => rating_id,
        'unified_users_id' => OWNER[:uuid],
        'body' => "UPDATE: Thank you so so very much #{@user.id}, tell your friends, come back soon!",
        'verified_business_owner' => true
    }

    put '/rats/rating_response', params
    assert_response(@response, :success)

    # Step 7
    params = {
        'rating_id' => rating_id,
        'unified_users_id' => OWNER[:uuid],
        'body' => "UPDATE2: You rock #{@user.id}! Tell your friends & come back soon!!",
        'verified_business_owner' => true
    }

    put '/rats/rating_response', params
    assert_response(@response, :success)

    # Step 8
    params = {
        'rating_id' => rating_id,
        'unified_users_id' => OWNER[:uuid]
    }

    delete '/rats/rating_response', params
    assert_response(@response, :success)

    # Step 9
    params = {
        'rating_id' => rating_id,
        'unified_users_id' => OWNER[:uuid],
        'body' => "FINAL POST: Thank you #{@user.id}, hope to see you again soon!",
        'verified_business_owner' => true
    }

    post '/rats/rating_response', params
    assert_response(@response, :success)

    # Cleanup (will only execute if test passes)
    params = {
        'rating_id' => rating_id,
        'unified_users_id' => OWNER[:uuid]
    }

    delete '/rats/rating_response', params

    assert_response(@response, :success)

    delete "/rats/#{rating_id}", {}
    assert_response(@response, :success)

    params = {
        'int_xxid' => OWNER[:int_xxid],
        'h' => 1000
    }

    get '/rats/business', params
    assert_response(@response, :success)
    assert @parsed_response['Ratings'].none? { |x| x['Id'] == rating_id }
  end
end
