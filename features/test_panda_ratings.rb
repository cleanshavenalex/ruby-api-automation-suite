require './init'

class TestPandaRatings < APITest
  RATING_KEYS = {
      main: ['Id','Value','Source','SourceId','AuthorName','AuthorUserId','CreatedAt','UpdatedAt','Suppressed',
             'PromoCode','ReceivedOn','Subject','Body','ListingId','ParentCustomerId','ThumbsUp','ThumbsDown','Int_Xxid',
             'ListingSource','ListingSourceId','Url','OrphanInd','Verified','UserInfo'],
      user_info: {
          main: ['User','Reviews','Images','CurrentUser'],
          user: ['AvatarURL','DisplayName','CreatedAt','Location','Verified'],
          count: ['Count']
      }
  }

  def setup
    assign_http(Config['panda']['host'])
  end

  ##
  # AS-7172 - Flag in /cons/business if the user has reviewed the business
  #
  # Steps:
  # 1. View a business before review and check that flag is false.
  # 2. Review the business.
  # 3. View the business after review and check that the flag is true.
  def test_user_already_reviewed_flag
    @user = setup_user

    get_consumer_search_resp('pizza', 'los angeles, ca')
    assert_response(@response, :success)
    business = @parsed_response['SearchResult']['BusinessListings'].sample

    # Step 1
    params = {
      'oauth_token' => @user.oauth_token,
      'int_xxid' => business['Int_Xxid']
    }

    get '/cons/business', params
    assert_response(@response, :success)
    refute(@parsed_response['Business']['IsReviewedByCurrentUser'])

    # Step 2
    params = {
      'oauth_token' => @user.oauth_token,
      'body' => "#{business['Name']} is a place I went to. I have neither negative nor positive feedback about it so this review is actually completely pointless.",
      'listing_id' => business['Int_Xxid'],
      'source' => 'CSE',
      'subject' => 'I am very neutral about this.',
      'value' => 3
    }
    put '/usr/reviews', params
    assert_response(@response, :success)

    # Step 3
    params = {
      'oauth_token' => @user.oauth_token,
      'int_xxid' => business['Int_Xxid']
    }

    get '/cons/business', params
    assert_response(@response, :success)
    assert(@parsed_response['Business']['IsReviewedByCurrentUser'])
  end

  ##
  # AS-6178 | API Test for User Endpoints
  # AS-7494 | Add flag to delete photos associated with reviews
  # - CrUD + GET '/usr/reviews' stack
  # Steps:
  # Setup
  # 1. Verify response, user1 & user2 adds reviews for businesses: PUT '/usr/reviews'
  # 1b. Verify error response for user2 on: PUT '/usr/reviews'
  # 2. Verify response, user1 & user2 update their reviews for the business: POST '/usr/reviews/:id'
  # 3. Verify response, retrieve reviews for the business: GET '/usr/reviews'
  # 4. Verify response, retrieve summary of reviews for the business: GET '/usr/reviews/summary'
  # 5. Verify response, user2 removed their review of the business: DELETE '/usr/reviews/:id'
  def test_user_reviews_stack
    # Setup
    @user1 = setup_user
    @user2 = setup_user

    get_consumer_search_resp('pizza', 'los angeles, ca')
    assert_response(@response, :success)
    businesses = @parsed_response['SearchResult']['BusinessListings']

    # Step 1
    user1_image_ids = []
    user2_image_ids = []
    user1_responses = []
    user2_responses = []
    caption = 'Check out this picture!'
    count = 0
    businesses[0..1].each do |business|
      user1_params = {
          'oauth_token' => @user1.oauth_token,
          'body' => "#{business['Name']} is the bomb! I love this pizza!!!!!!!!!!!!!",
          'listing_id' => business['Int_Xxid'],
          'source' => 'CSE',
          'subject' => '#BOOM!',
          'value' => 4
      }

      put '/usr/reviews', user1_params
      assert_response(@response, :success)
      assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
      assert(@parsed_response['RatingID'], @parsed_response)
      assert_has_keys(@parsed_response['Rating'], RATING_KEYS[:main])
      assert_has_keys(@parsed_response['Rating']['UserInfo'], RATING_KEYS[:user_info][:main])
      assert_has_keys(@parsed_response['Rating']['UserInfo']['User'], RATING_KEYS[:user_info][:user])
      assert_has_keys(@parsed_response['Rating']['UserInfo']['Reviews'], RATING_KEYS[:user_info][:count])
      assert_has_keys(@parsed_response['Rating']['UserInfo']['Images'], RATING_KEYS[:user_info][:count])
      user1_responses << @parsed_response

      opts = {
          'rating_id' => @parsed_response['RatingID']
      }

      upload_and_link_image_for_int_xxid_by_user(business['Int_Xxid'], @user1, generate_random_image, caption, opts)
      assert_response(@response, :success)
      user1_image_ids << @parsed_response['id']

      user2_params = {
          'oauth_token' => @user2.oauth_token,
          'listing_id' => business['Int_Xxid'],
          'source' => 'CSE',
          'subject' => 'Ok',
          'value' => 3
      }

      # Step 1b
      if count == 0
        user2_params['body'] = 'The Pizza is alright.'

        put '/usr/reviews', user2_params
        assert_response(@response, :client_error)
        assert_equal("We are sorry, but your review must be at least 25 to atmost 4000 characters long.", @parsed_response['Errors'].first)
      end

      user2_params['body'] = 'The Pizza is alright, decent beers on tap.'

      put '/usr/reviews', user2_params
      assert_response(@response, :success)
      assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
      assert(@parsed_response['RatingID'], @parsed_response)
      assert_has_keys(@parsed_response['Rating'], RATING_KEYS[:main])
      assert_has_keys(@parsed_response['Rating']['UserInfo'], RATING_KEYS[:user_info][:main])
      assert_has_keys(@parsed_response['Rating']['UserInfo']['User'], RATING_KEYS[:user_info][:user])
      assert_has_keys(@parsed_response['Rating']['UserInfo']['Reviews'], RATING_KEYS[:user_info][:count])
      assert_has_keys(@parsed_response['Rating']['UserInfo']['Images'], RATING_KEYS[:user_info][:count])
      user2_responses << @parsed_response

      opts = {
          'rating_id' => @parsed_response['RatingID']
      }

      upload_and_link_image_for_int_xxid_by_user(business['Int_Xxid'], @user2, generate_random_image, caption, opts)
      assert_response(@response, :success)
      user2_image_ids << @parsed_response['id']

      # Step 2
      params = {
          'oauth_token' => @user1.oauth_token,
          'rating' => {
              'value' => 5
          },
          'images' => user1_image_ids
      }

      post "/usr/reviews/#{user1_responses[count]['RatingID']}", params
      assert_response(@response, :success)
      assert_equal(user1_responses[count]['RatingID'], @parsed_response['id'], @parsed_response)
      assert_equal(params['rating']['value'], @parsed_response['value'], @parsed_response)
      assert_equal(user1_responses[count]['Rating']['AuthorUserId'], @parsed_response['author_user_id'], @parsed_response)

      params = {
          'oauth_token' => @user2.oauth_token,
          'rating' => {
              'subject' => 'Decent Pizza'
          },
          'images' => user2_image_ids
      }

      post "/usr/reviews/#{user2_responses[count]['RatingID']}", params
      assert_response(@response, :success)
      assert_equal(user2_responses[count]['RatingID'], @parsed_response['id'], @parsed_response)
      assert_equal(params['rating']['subject'], @parsed_response['subject'], @parsed_response)
      assert_equal(user2_responses[count]['Rating']['AuthorUserId'], @parsed_response['author_user_id'], @parsed_response)

      # Step 3
      params = {
          'user_id' => @user1.id
      }

      get '/usr/reviews', params
      assert_response(@response, :success)
      response = @parsed_response.first
      assert_equal(5, response['value'], @parsed_response)

      params['user_id'] = @user2.id

      get '/usr/reviews', params
      assert_response(@response, :success)
      response = @parsed_response.first
      assert_equal('Decent Pizza', response['subject'], @parsed_response)

      count += 1
    end

    # Step 4
    params = {
        'user_id' => @user2.id
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)
    assert_equal(2, @parsed_response['review_count'], @parsed_response)
    assert_equal(2, @parsed_response['image_count'], @parsed_response)

    assign_http(Config['monkey']['host'])

    rating_ids = ["#{user2_responses[0]['RatingID']}","#{user2_responses[1]['RatingID']}"]

    monkey_params = {
        'api_key' => Config['monkey']['api_key'],
        'ids' => rating_ids
    }

    get '/media/reviews', monkey_params
    assert_response(@response, :success)
    assert(@parsed_response["#{user2_responses[0]['RatingID']}"]['images'][0]['id'], @parsed_response)
    assert(@parsed_response["#{user2_responses[1]['RatingID']}"]['images'][0]['id'], @parsed_response)

    # Step 5
    assign_http(Config['panda']['host'])

    params = {
        'oauth_token' => @user2.oauth_token,
        'delete_linked_images' => true
    }

    delete "/usr/reviews/#{user2_responses[0]['RatingID']}", params
    assert_response(@response, :success)

    params = {
        'user_id' => @user2.id
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['review_count'], @parsed_response)
    assert_equal(1, @parsed_response['image_count'], @parsed_response)

    assign_http(Config['monkey']['host'])

    get '/media/reviews', monkey_params
    assert_response(@response, :success)
    assert(@parsed_response["#{user2_responses[1]['RatingID']}"]['images'][0]['id'], @parsed_response)

    assign_http(Config['panda']['host'])

    get '/usr/reviews', params
    assert_response(@response, :success)
    assert_equal(user2_responses[1]['RatingID'], @parsed_response[0]['id'], @parsed_response)
  end

  ##
  # AS-6922 | /usr/:id/reviews endpoint default and filters
  # ~ GET '/usr/id/reviews' (default = any)
  #
  # Steps:
  # Setup: Unverified user & businesses
  # 1. Verified & Unverified users add ratings for multiple businesses: PUT '/usr/reviews'
  # 2. Verify responses for filters on unverified user account: GET '/usr/:id/reviews'
  # 3. Verify responses for filters on verified user account: GET '/usr/:id/reviews'
  def test_user_id_reviews_response_default_and_filters
    # Setup
    @verified_user = setup_user({ 'first_name' => 'verified' })

    @unverified_user = TurtleUser.new({ 'first_name' => 'unverified' })
    turtle_response = @unverified_user.register
    assert_response(turtle_response, :success)
    turtle_response = @unverified_user.login
    assert_response(turtle_response, :success)
    assert(@unverified_user.id, turtle_response.body)

    get_consumer_search_resp('pizza', 'los angeles, ca')
    assert_response(@response, :success)

    refute_empty(@parsed_response['SearchResult']['BusinessListings'], @parsed_response['SearchResult'])

    businesses = []
    businesses << @parsed_response['SearchResult']['BusinessListings'][0]
    businesses << @parsed_response['SearchResult']['BusinessListings'][1]

    # Step 1
    params = {
        'user_id' => @unverified_user.id,
        'body' => "#{businesses[0]['Name']} is the bomb! I love this pizza!!!!!!!!!!!!!",
        'listing_id' => businesses[0]['Int_Xxid'],
        'source' => 'CSE',
        'subject' => '#BOOM!',
        'value' => 4
    }

    put '/usr/reviews', params
    assert_response(@response, :success)

    assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
    assert(@parsed_response['RatingID'], @parsed_response)

    params['user_id'] = @verified_user.id

    put '/usr/reviews', params
    assert_response(@response, :success)

    assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
    assert(@parsed_response['RatingID'], @parsed_response)

    params['body'] = 'The Pizza is alright, decent beers on tap.'
    params['listing_id'] = businesses[1]['Int_Xxid']
    params['subject'] = 'Ok'
    params['value'] = 3

    put '/usr/reviews', params
    assert_response(@response, :success)

    assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
    assert(@parsed_response['RatingID'], @parsed_response)

    params['user_id'] = @unverified_user.id

    put '/usr/reviews', params
    assert_response(@response, :success)

    assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
    assert(@parsed_response['RatingID'], @parsed_response)

    # Step 2
    get "/usr/#{@unverified_user.id}/reviews?verified==true", {}
    assert_response(@response, :success)

    assert_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(0, @parsed_response['count'], @parsed_response)

    get "/usr/#{@unverified_user.id}/reviews?verified=false", {}
    assert_response(@response, :success)

    refute_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(2, @parsed_response['count'], @parsed_response)

    response = @parsed_response

    get "/usr/#{@unverified_user.id}/reviews", {}
    assert_response(@response, :success)

    refute_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(2, @parsed_response['count'], @parsed_response)

    @parsed_response['reviews'].each do |rating|
      assert(rating['id'], rating)
      assert(rating['value'], rating)
      assert(rating['source'], rating)
      assert(rating['source_id'], rating)
      assert(rating['author_name'], rating)
      assert_equal(@unverified_user.id, rating['author_user_id'], rating)
      assert(rating['subject'], rating)
      assert(rating['body'], rating)
      assert(rating['listing_id'], rating)
      assert(rating['int_xxid'], rating)
      assert_equal(false, rating['verified'], rating)
      assert(rating['business'], rating)
    end

    get "/usr/#{@unverified_user.id}/reviews?verified=any", {}
    assert_response(@response, :success)

    refute_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(2, @parsed_response['count'], @parsed_response)

    assert_equal(response, @parsed_response, 'Responses for verified false : any do not match.')

    # Step 3
    assign_http(Config['panda']['host'])

    get "/usr/#{@verified_user.id}/reviews?verified=false", {}
    assert_response(@response, :success)

    assert_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(0, @parsed_response['count'], @parsed_response)

    get "/usr/#{@verified_user.id}/reviews?verified=true", {}
    assert_response(@response, :success)

    refute_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(2, @parsed_response['count'], @parsed_response)

    response = @parsed_response

    @parsed_response['reviews'].each do |rating|
      assert(rating['id'], rating)
      assert(rating['value'], rating)
      assert(rating['source'], rating)
      assert(rating['source_id'], rating)
      assert(rating['author_name'], rating)
      assert_equal(@verified_user.id, rating['author_user_id'], rating)
      assert(rating['subject'], rating)
      assert(rating['body'], rating)
      assert(rating['listing_id'], rating)
      assert(rating['int_xxid'], rating)
      assert_equal(true, rating['verified'], rating)
      assert(rating['business'], rating)
    end

    get "/usr/#{@verified_user.id}/reviews?verified=any", {}
    assert_response(@response, :success)

    refute_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(2, @parsed_response['count'], @parsed_response)

    get "/usr/#{@verified_user.id}/reviews", {}
    assert_response(@response, :success)

    refute_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(2, @parsed_response['count'], @parsed_response)

    assert_equal(response, @parsed_response, 'Responses for verified true : any do not match.')
  end

  ##
  # AS-6984 | /usr/reviews/summary endpoint default and filters
  # ~ GET '/usr/reviews/summary?user_id=123&verified=option' (default = any)
  #
  # Steps:
  # Setup: Unverified user & businesses
  # 1. Verified & Unverified users add ratings for multiple businesses: PUT '/usr/reviews'
  # 2. Verify responses for filters on unverified user account: GET '/usr/reviews/summary'
  # 3. Verify responses for filters on verified user account: GET '/usr/reviews/summary'
  def test_user_reviews_summary_response_default_and_filters
    # Setup
    @verified_user = setup_user({ 'first_name' => 'verified' })

    @unverified_user = TurtleUser.new({ 'first_name' => 'unverified' })
    turtle_response = @unverified_user.register
    assert_response(turtle_response, :success)
    turtle_response = @unverified_user.login
    assert_response(turtle_response, :success)
    assert(@unverified_user.id, turtle_response.body)
    turtle_response = @unverified_user.login_oauth
    assert(@unverified_user.oauth_token, turtle_response.body)

    get_consumer_search_resp('pizza', 'los angeles, ca')
    assert_response(@response, :success)

    refute_empty(@parsed_response['SearchResult']['BusinessListings'], @parsed_response['SearchResult'])

    businesses = []
    businesses << @parsed_response['SearchResult']['BusinessListings'][0]
    businesses << @parsed_response['SearchResult']['BusinessListings'][1]

    # Step 1
    params = {
        'user_id' => @unverified_user.id,
        'body' => "#{businesses[0]['Name']} is the bomb! I love this pizza!!!!!!!!!!!!!",
        'listing_id' => businesses[0]['Int_Xxid'],
        'source' => 'CSE',
        'subject' => '#BOOM!',
        'value' => 4
    }

    put '/usr/reviews', params
    assert_response(@response, :success)

    assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
    assert(@parsed_response['RatingID'], @parsed_response)

    params['user_id'] = @verified_user.id

    put '/usr/reviews', params
    assert_response(@response, :success)

    assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
    assert(@parsed_response['RatingID'], @parsed_response)

    params['body'] = 'The Pizza is alright, decent beers on tap.'
    params['listing_id'] = businesses[1]['Int_Xxid']
    params['subject'] = 'Ok'
    params['value'] = 3

    put '/usr/reviews', params
    assert_response(@response, :success)

    assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
    assert(@parsed_response['RatingID'], @parsed_response)

    params['user_id'] = @unverified_user.id

    put '/usr/reviews', params
    assert_response(@response, :success)

    assert_equal('Added Rating', @parsed_response['Message'], @parsed_response)
    assert(@parsed_response['RatingID'], @parsed_response)

    businesses.each do |business|
      int_xxid = business['Int_Xxid']
      upload_and_link_image_for_int_xxid_by_user(int_xxid, @unverified_user)
      upload_and_link_image_for_int_xxid_by_user(int_xxid, @verified_user)
    end

    # Step 2
    params = {
        'user_id' => @unverified_user.id,
        'verified' => 'true',
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)

    assert_equal(0, @parsed_response['review_count'], @parsed_response)
    assert_equal(0, @parsed_response['image_count'], @parsed_response)

    params = {
        'user_id' => @unverified_user.id,
        'verified' => 'false',
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)

    assert_equal(2, @parsed_response['review_count'], @parsed_response)
    assert_equal(2, @parsed_response['image_count'], @parsed_response)
    response = @parsed_response

    params = {
        'user_id' => @unverified_user.id,
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)

    assert_equal(2, @parsed_response['review_count'], @parsed_response)
    assert_equal(2, @parsed_response['image_count'], @parsed_response)

    params = {
        'user_id' => @unverified_user.id,
        'verified' => 'any',
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)

    assert_equal(2, @parsed_response['review_count'], @parsed_response)
    assert_equal(2, @parsed_response['image_count'], @parsed_response)

    assert_equal(response, @parsed_response, 'Responses for verified false : any do not match.')

    # Step 3
    assign_http(Config['panda']['host'])

    params = {
        'user_id' => @verified_user.id,
        'verified' => 'false',
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)

    assert_equal(0, @parsed_response['review_count'], @parsed_response)
    assert_equal(0, @parsed_response['image_count'], @parsed_response)

    params = {
        'user_id' => @verified_user.id,
        'verified' => 'true',
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)

    assert_equal(2, @parsed_response['review_count'], @parsed_response)
    assert_equal(2, @parsed_response['image_count'], @parsed_response)
    response = @parsed_response

    params = {
        'user_id' => @verified_user.id,
        'verified' => 'any',
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)

    assert_equal(2, @parsed_response['review_count'], @parsed_response)
    assert_equal(2, @parsed_response['image_count'], @parsed_response)

    params = {
        'user_id' => @verified_user.id,
    }

    get '/usr/reviews/summary', params
    assert_response(@response, :success)

    assert_equal(2, @parsed_response['review_count'], @parsed_response)
    assert_equal(2, @parsed_response['image_count'], @parsed_response)

    assert_equal(response, @parsed_response, 'Responses for verified true : any do not match.')
  end

  ##
  # AS-7264 | Set the listing's int_xxid to the rating's int_xxid in case the lid is passed instead of int_xxid when creating a review
  #
  # Steps
  # 1. Get a rateable int_xxid from search.
  # 2. Convert to a listing_id via Rhino
  # 3. Review the business with the listing_id
  # 4. Check that the review appears on the business
  def test_passing_listing_id_converts_to_int_xxid_on_new_rating
    @user = setup_user

    # Step 1
    int_xxid = get_rateable_int_xxids_from_search('attorneys', 'new york city, ny').first
    assert(int_xxid, 'Did not get a int_xxid from search')

    # Step 2
    assign_http(Config['rhino']['host'])
    get '/thanos/listings/int_xxid', {'q' => int_xxid}
    assert_response(@response, :success)
    lid = @parsed_response['Results'].sample['ListingId']

    # Step 3
    rating_id = review_business(lid, @user.oauth_token)

    # Step 4
    get_consumer_business_resp(int_xxid)
    assert_response(@response, :success)

    ratings = @parsed_response['Business']['Ratings']
    refute_empty(ratings, "Business ratings are empty when they shouldn't be")

    matching_rating = ratings.find { |rating| rating['Id'] == rating_id }
    assert(matching_rating, "Business ratings did not include the expected rating")
  end

  ##
  # AS-7306 | Endpoint for tools for to return suppressed and unsuppressed reviews
  #
  # Steps
  # Setup
  # 1. Verify response for basic GET all ratings for int_xxid
  # 2. Verify response for basic GET all ratings for int_xxid + sorting updated_at:desc & updated_at:asc
  # 3. Verify response for basic GET all ratings for int_xxid + min_rating & body
  # 4. Verify response for basic GET all ratings for int_xxid + limit & offset
  # 5. Verify response for basic GET all ratings for int_xxid + start & end date
  def test_retrieve_all_ratings_for_business
    # Setup

    queries = ['attorneys','restaurants','plumbers']
    locations = ['new york city, ny','chicago, il','los angeles, ca']
    listings = []

    queries.each do |query|
      locations.each do |location|
        get_consumer_search_resp(query, location)
        assert_response(@response, :success)
        refute_empty(@parsed_response['SearchResult']['BusinessListings'])
        @parsed_response['SearchResult']['BusinessListings'].each do |business|
          if business['RatingCount'] >= 10
            get_consumer_business_resp(business['Int_Xxid'])
            assert_response(@response, :success)
            listings << @parsed_response['Business'] if @parsed_response['Business']['Ratings'].length >= 3
          end
        end
      end
    end
    refute_empty("Response returned no listing with at least 3 or more reviews: #{queries}, #{locations}")
    listing = listings.sample

    # Step 1
    params = { 'int_xxid' => listing['Int_Xxid'] }

    get '/rats/get_all_ratings_for_business', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Ratings'])
    ratings_full_list = @parsed_response['Ratings']
    if @parsed_response['Count'] >= 25
      assert_equal(25, ratings_full_list.length, "Expected the default limit of 25, returned: #{@parsed_response['Count']}")
    end
    @parsed_response['Ratings'].each do |rating|
      assert(rating['id'])
      assert_equal(listing['Int_Xxid'], rating['int_xxid'].to_s)
      assert(rating['updated_at'])
    end

    # Step 2
    params['s'] = 'updated_at:desc'

    get '/rats/get_all_ratings_for_business', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Ratings'])
    check_rating = @parsed_response['Ratings'].first
    @parsed_response['Ratings'].each do |rating|
      assert(rating['id'])
      assert_equal(listing['Int_Xxid'], rating['int_xxid'].to_s)
      assert(rating['updated_at'])
      assert(DateTime.parse(check_rating['updated_at']).to_i >= DateTime.parse(rating['updated_at']).to_i,
             "Expected sort updated_at:desc -- #{DateTime.parse(check_rating['updated_at']).to_i} >= #{DateTime.parse(rating['updated_at']).to_i}")
      check_rating = rating
    end

    params['s'] = 'updated_at:asc'

    get '/rats/get_all_ratings_for_business', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Ratings'])
    check_rating = @parsed_response['Ratings'].first
    @parsed_response['Ratings'].each do |rating|
      assert(rating['id'])
      assert_equal(listing['Int_Xxid'], rating['int_xxid'].to_s)
      assert(rating['updated_at'])
      assert(DateTime.parse(check_rating['updated_at']).to_i <= DateTime.parse(rating['updated_at']).to_i,
             "Expected sort updated_at:asc -- #{DateTime.parse(check_rating['updated_at']).to_i} <= #{DateTime.parse(rating['updated_at']).to_i}")
      check_rating = rating
    end

    # Step 3
    params = {
        'int_xxid' => listing['Int_Xxid'],
        'min_rating' => 4,
        'body_required' => true
    }

    get '/rats/get_all_ratings_for_business', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Ratings'])
    @parsed_response['Ratings'].each do |rating|
      assert(rating['id'])
      assert_equal(listing['Int_Xxid'], rating['int_xxid'].to_s)
      assert(rating['value'] >= 4)
      assert(rating['body'])
    end

    # Step 4
    limit = (@parsed_response['Count'] - 1)
    params = {
        'int_xxid' => listing['Int_Xxid'],
        'h' => limit
    }

    get '/rats/get_all_ratings_for_business', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Ratings'])
    assert_equal(limit, @parsed_response['Ratings'].length)
    @parsed_response['Ratings'].each do |rating|
      assert(rating['id'])
      assert_equal(listing['Int_Xxid'], rating['int_xxid'].to_s)
    end
    limited_ratings = @parsed_response['Ratings']

    params['o'] = 2

    get '/rats/get_all_ratings_for_business', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Ratings'])
    assert_equal(limited_ratings[2], @parsed_response['Ratings'][0])
    @parsed_response['Ratings'].each do |rating|
      assert(rating['id'])
      assert_equal(listing['Int_Xxid'], rating['int_xxid'].to_s)
    end

    # Step 5
    rating_dates = []
    ratings_full_list.each do |rating|
      rating_dates << rating['created_at']
    end

    val = (rating_dates.length / 4).to_f.ceil
    date = DateTime.parse(rating_dates[val]).to_i
    params = {
        'int_xxid' => listing['Int_Xxid'],
        'start_date' => date
    }

    get '/rats/get_all_ratings_for_business', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Ratings'])
    @parsed_response['Ratings'].each do |rating|
      assert(rating['id'])
      assert_equal(listing['Int_Xxid'], rating['int_xxid'].to_s)
      assert(DateTime.parse(rating['created_at']).to_i >= date,
             "Expected all dates returned after the start_date specified: #{date} <= #{DateTime.parse(rating['created_at']).to_i}")
    end

    val = (rating_dates.length / 2).to_f.ceil
    date = DateTime.parse(rating_dates[val]).to_i
    params = {
        'int_xxid' => listing['Int_Xxid'],
        'end_date' => date
    }

    get '/rats/get_all_ratings_for_business', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Ratings'])
    @parsed_response['Ratings'].each do |rating|
      assert(rating['id'])
      assert_equal(listing['Int_Xxid'], rating['int_xxid'].to_s)
      assert(DateTime.parse(rating['created_at']).to_i <= date,
             "Expected all dates returned prior the end_date specified: #{date} -- #{DateTime.parse(rating['created_at']).to_i}")
    end
  end

  ##
  # AS-7345 | Mobile Support: Public profile
  # AS-7344 | Mobile Support: User's profile
  # AS-7440 | Remove marked reviews from 'user/:id/reviews' endpoint
  #
  # Steps
  # Setup: Users and Int_Xxids
  # 1. Verify empty responses for /usr/:id/reviews
  # 2. Verify response for adding multiple reviews for each user
  # 3. Verify response for adding scores for each user
  # 4. Verify responses for /usr/:id/reviews after reviews and scores
  # 5. Verify snake responses for /usr/:id/reviews after reviews and scores
  def test_profiles_for_mobile_support
    # Setup
    @user1 = setup_user
    @user2 = setup_user

    int_xxids = get_rateable_int_xxids_from_search('restaurants', 'los angeles, ca').shuffle!
    refute_empty(int_xxids)

    # Step 1
    get "/usr/#{@user1.id}/reviews", {}
    assert_response(@response, :success)
    assert_empty(@parsed_response['reviews'])
    assert_equal(0, @parsed_response['total_helpful_votes'])
    assert_equal(0, @parsed_response['count'])

    get "/usr/#{@user2.id}/reviews", {}
    assert_response(@response, :success)
    assert_empty(@parsed_response['reviews'])
    assert_equal(0, @parsed_response['total_helpful_votes'])
    assert_equal(0, @parsed_response['count'])

    # Step 2
    user1_rating_ids = []
    int_xxids[0..3].each do |int_xxid|
      user1_rating_ids << review_business(int_xxid, @user1.oauth_token)
    end
    assert_equal(4, user1_rating_ids.length, 'Expected 4 reviews for User 1.')

    user2_rating_ids = []
    int_xxids[2..4].each do |int_xxid|
      user2_rating_ids << review_business(int_xxid, @user2.oauth_token)
    end
    assert_equal(3, user2_rating_ids.length, 'Expected 3 reviews for User 2.')

    # Step 3
    params = {
        'rating_score' => {
            'rating_id' => user1_rating_ids.sample,
            'user_id' => @user2.id,
            'score' => 1,
        }
    }

    post '/rats/scores', params
    assert_response(@response, :success)

    count = 0
    user2_rating_ids.each do |rating_id|
      count <= 1 ? score = 1 : score = -1

      params = {
          'rating_score' => {
              'rating_id' => rating_id,
              'user_id' => @user1.id,
              'score' => score,
          }
      }

      post '/rats/scores', params
      assert_response(@response, :success)

      count += 1
    end

    # Step 4
    get "/usr/#{@user1.id}/reviews", {}
    assert_response(@response, :success)

    # reviews
    refute_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(user1_rating_ids.length, @parsed_response['reviews'].length,
                 "Expected response for reviews: #{@parsed_response['reviews']} to match total submitted by user 1.")
    @parsed_response['reviews'].each do |review|
      assert(review['id'], review)
      assert(user1_rating_ids.find { |rating_id| rating_id == review['id'] },
             "Expected to find matching rating id: #{review['id']} within original user1_rating_ids: #{user1_rating_ids}")
    end
    # total_helpful_votes
    assert_equal(1, @parsed_response['total_helpful_votes'],
                 "Expected response for total_helpful_votes: #{@parsed_response['total_helpful_votes']} to match total submitted by user 2.")
    # count
    assert_equal(user1_rating_ids.length, @parsed_response['count'],
                 "Expected response for count: #{@parsed_response['count']} to match total submitted by user 1.")

    # Step 5
    assign_http(Config['snake']['host'])

    params = { 'api_key' => Config['snake']['api_key'] }

    get "/snake/usr/#{@user1.id}/reviews", params
    assert_response(@response, :success)

    # reviews
    refute_empty(@parsed_response['reviews'], @parsed_response)
    assert_equal(user1_rating_ids.length, @parsed_response['reviews'].length,
                 "Expected response for reviews: #{@parsed_response['reviews']} to match total submitted by user 1.")
    @parsed_response['reviews'].each do |review|
      assert(review['id'], review)
      assert(user1_rating_ids.find { |rating_id| rating_id == review['id'] },
             "Expected to find matching rating id: #{review['id']} within original user1_rating_ids: #{user1_rating_ids}")
    end
    # total_helpful_votes
    assert_equal(1, @parsed_response['total_helpful_votes'],
                 "Expected response for total_helpful_votes: #{@parsed_response['total_helpful_votes']} to match total submitted by user 2.")
    # count
    assert_equal(user1_rating_ids.length, @parsed_response['count'],
                 "Expected response for count: #{@parsed_response['count']} to match total submitted by user 1.")
  end

  ##
  # AS-7458 | Upload, display and delete endpoints for photos associated with reviews
  # AS-7315 | Endpoint needed to upload and display photos associated with reviews (associated ticket)
  #
  # Steps:
  # Setup
  # 1. User adds reviews and images
  # 2. Verify response for get '/media/reviews'
  # 3. User updates reviews
  # 4. Verify response for get '/media/reviews' still linked to int_xxid / review
  # 5. Verify response for delete '/media/:sha1/listings/:int_xxid'
  def test_media_reviews_by_rating_id
    # Setup
    @user = setup_user

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

    int_xxids = []
    @parsed_response['SearchResult']['BusinessListings'].each do |business|
      if business['Rateable'] == 1 && business['Int_Xxid']
        int_xxids << business['Int_Xxid']
        break if int_xxids.length == 4
      end
    end

    review_business_later = int_xxids.pop

    # Step 1
    get "/usr/#{@user.id}/reviews", {}
    assert_response(@response, :success)
    assert_empty(@parsed_response['reviews'])
    assert_equal(0, @parsed_response['count'])

    # Step 2
    caption = 'Check out this picture!'
    images = []
    rating_ids = []

    count = 0
    int_xxids.each do |int_xxid|
      upload_image(@user.oauth_token)
      assert_response(@response, :success)
      images << @parsed_response

      params = {
          'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
          'source' => 'CSE',
          'subject' => 'Review made by API',
          'value' => 3,
          'int_xxid' => int_xxid,
          'oauth_token' => @user.oauth_token,
          'images' => [
              {
                  'id' => @parsed_response['id'],
                  'caption' => caption
              },
          ]
      }

      if count > 1
        upload_image(@user.oauth_token)
        assert_response(@response, :success)
        images << @parsed_response

        params['images'] << {
            'id' => @parsed_response['id'],
            'caption' => caption
        }
      end

      put '/usr/reviews', params
      assert_response(@response, :success)
      assert(@parsed_response['Message'])
      assert_equal('Added Rating', @parsed_response['Message'])
      assert(@parsed_response['RatingID'])
      rating_ids << @parsed_response['RatingID']
      assert(@parsed_response['Rating'], @parsed_response)
      rating = @parsed_response['Rating']
      assert_equal(@user.id, rating['AuthorUserId'])
      assert_equal(params['body'], rating['Body'])
      assert_equal(params['source'], rating['Source'])
      assert_equal(params['subject'], rating['Subject'])
      assert_equal(params['value'], rating['Value'])
      assert_equal(params['int_xxid'].to_i, rating['Int_Xxid'])
      assert(rating['UserInfo'], rating)
      assert_equal(rating_ids.length, rating['UserInfo']['Reviews']['Count'])
      assert_equal(images.length, rating['UserInfo']['Images']['Count'])

      count += 1
    end

    # Step 3
    assign_http(Config['monkey']['host'])
    api_key = Config['monkey']['api_key']

    params = {
        'api_key' => api_key,
        'ids' => rating_ids
    }

    get '/media/reviews', params
    assert_response(@response, :success)
    refute_empty(@parsed_response, 'Endpoint: /media/reviews')
    media_reviews_resp = @parsed_response

    media_reviews_images = []
    rating_ids.each do |rating_id|
      assert_equal(media_reviews_resp[rating_id]['images'].length, media_reviews_resp[rating_id]['count'])

      media_reviews_resp[rating_id]['images'].each do |image|
        assert(images.find { |i| i['id'] == image['id'] }, 'Expected image id to match initial upload')
        assert_equal(@user.id, image['user_id'])
        assert_equal('xx', image['user_type'])
        assert_equal('int_xxid', image['type_name'])
        assert_equal('public', image['state_name'])
        assert_equal('image', image['b_image_media_type'])
        assert_equal(caption, image['caption'])
        assert(int_xxids.include?(image['ext_id']),
               "Expected image ext_id #{image['ext_id']} to match int_xxid from initial upload: #{int_xxids}")

        media_reviews_images << image
      end
    end

    # Step 3
    assign_http(Config['panda']['host'])

    rating_ids.each do |rating_id|
      params = {
          'oauth_token' => @user.oauth_token,
          'id' => rating_id,
          'rating' => {
              'body' => 'It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness...',
              'value' => 5
          }
      }

      post "/usr/reviews/#{rating_id}", params
      assert_response(@response, :success)
    end

    # Step 4
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => api_key,
        'ids' => rating_ids
    }

    get '/media/reviews', params
    assert_response(@response, :success)
    refute_empty(@parsed_response, 'Endpoint: /media/reviews')

    rating_ids.each do |rating_id|
      assert_equal(@parsed_response[rating_id]['images'].length, @parsed_response[rating_id]['count'])

      @parsed_response[rating_id]['images'].each do |image|
        assert(media_reviews_images.find { |i| i['id'] == image['id'] }, 'Expected image id to match initial upload')
        assert_equal(@user.id, image['user_id'])
        assert_equal('xx', image['user_type'])
        assert_equal('int_xxid', image['type_name'])
        assert_equal('public', image['state_name'])
        assert_equal('image', image['b_image_media_type'])
        assert_equal(caption, image['caption'])
        assert(int_xxids.include?(image['ext_id']),
               "Expected image ext_id #{image['ext_id']} to match int_xxid from initial upload: #{int_xxids}")
      end
    end

    # Step 5
    rating_ids.shuffle!
    deleted_rating_id = rating_ids.pop
    media_info = media_reviews_resp[deleted_rating_id]

    assign_http(Config['panda']['host'])

    params = {
        'oauth_token' => @user.oauth_token,
        'id' => deleted_rating_id,
        'image_ids' => [
            media_info['images'][0]['id']
        ]
    }

    if media_info['images'].length > 1
      media_info['images'].each do |image|
        params['image_ids'] << image['id']
      end
    end

    delete "/usr/reviews/#{deleted_rating_id}", params
    assert_response(@response, :success)

    # Step 6
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => api_key,
        'ids' => rating_ids
    }

    get '/media/reviews', params
    assert_response(@response, :success)
    refute_empty(@parsed_response, 'Endpoint: /media/reviews')

    rating_ids.each do |rating_id|
      assert_equal(@parsed_response[rating_id]['images'].length, @parsed_response[rating_id]['count'])

      @parsed_response[rating_id]['images'].each do |image|
        assert(media_reviews_images.find { |i| i['id'] == image['id'] }, 'Expected image id to match initial upload')
        assert_equal(@user.id, image['user_id'])
        assert_equal('xx', image['user_type'])
        assert_equal('int_xxid', image['type_name'])
        assert_equal('public', image['state_name'])
        assert_equal('image', image['b_image_media_type'])
        assert_equal(caption, image['caption'])
        assert(int_xxids.include?(image['ext_id']),
               "Expected image ext_id #{image['ext_id']} to match int_xxid from initial upload: #{int_xxids}")
      end
    end

    # Step 7
    assign_http(Config['panda']['host'])

    params = {
        'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
        'source' => 'CSE',
        'subject' => 'Review made by API',
        'value' => 3,
        'int_xxid' => review_business_later,
        'oauth_token' => @user.oauth_token,
    }

    put '/usr/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Message'])
    assert_equal('Added Rating', @parsed_response['Message'])
    assert(@parsed_response['RatingID'])
    rating_id_no_image = @parsed_response['RatingID']
    rating_ids << rating_id_no_image
    assert(@parsed_response['Rating'], @parsed_response)
    assert_equal(@user.id, @parsed_response['Rating']['AuthorUserId'])
    assert_equal(params['body'], @parsed_response['Rating']['Body'])
    assert_equal(params['source'], @parsed_response['Rating']['Source'])
    assert_equal(params['subject'], @parsed_response['Rating']['Subject'])
    assert_equal(params['value'], @parsed_response['Rating']['Value'])
    assert_equal(params['int_xxid'].to_i, @parsed_response['Rating']['Int_Xxid'])

    # Step 8
    params = {
        'include_images' => true,
        'only_review_images' => true
    }

    get "/usr/#{@user.id}/reviews", params
    assert_response(@response, :success)
    refute_empty(@parsed_response['reviews'])
    assert_equal(rating_ids.length, @parsed_response['reviews'].length)

    @parsed_response['reviews'].each do |rating|
      refute_equal(deleted_rating_id, rating['id'])

      if rating['id'] == rating_id_no_image
        assert_equal(review_business_later.to_i, rating['int_xxid'])
        refute(rating['business']['images'],
               "Expected image to be blank for rating id #{rating_id_no_image}: #{rating['business']['image']}")
      else
        assert(int_xxids.include?(rating['int_xxid'].to_s))
        refute_empty(rating['business']['images'],
               "Expected image(s) returned for rating id #{rating['id']}: #{rating['business']}")
        assert_equal(rating['business']['images'].length, rating['business']['image_count'])
        rating['business']['images'].each do |image|
          assert_equal(@user.id, image['user_id'])
          assert_equal('xx', image['user_type'])
          assert_equal('int_xxid', image['type_name'])
          assert_equal('public', image['state_name'])
          assert_equal('image', image['b_image_media_type'])
          assert_equal(caption, image['caption'])
          assert_equal(rating['int_xxid'].to_s, image['ext_id'])
        end
      end
    end
  end
end
