require './init'

class TestPromosModeration < APITest
  def setup
    @active_promo = 'APIACTIVEPROMO'
    @promo = get_promo_with_code(@active_promo)
    @active_promo_id = @promo['Id']
    @active_promo_points = get_promo_points(@active_promo_id)

    assign_http(Config['panda']['host'])
  end

  def teardown
    delete_matching_promos
  end

  # Steps:
  # 1. Look up a promo and check current contributed points.
  # 2. Add a positive bonus contribution to the promo.
  # 3. Check the promo and see that it's updated.
  # 4. Add a negative bonus contribution to the promo.
  # 5. Check the promo and see that it's updated.
  # 6. Check that the bonus transactions are tracked.
  def test_promo_bonus_contributions
    bonus_points = rand(100..200) # random points from 100 to 200
    transactions = []

    # Step 1
    params = { 'promo_id' => @active_promo_id }

    get '/pros/lookup', params
    assert_response(@response, :success)
    orig_contrib_points = @parsed_response['Promo']['ContributedPoints']

    # Step 2
    params = {
      'promo_id' => @active_promo_id,
      'points' => bonus_points,
      'moderator_id' => 'App Services'
    }

    post '/pros/bonus', params
    assert_response(@response, :client_error)
    assert_equal('InvalidParamsError', @parsed_response['error'])
    assert_equal("parameter(s) [\"points\", \"promo_id\", \"moderator_id\", \"notes\"] must not be blank", @parsed_response['message'])

    params['notes'] = 'API Test'

    post '/pros/bonus', params
    assert_response(@response, :success)
    transactions << @parsed_response['Bonus']

    # Step 3
    params = { 'promo_id' => @active_promo_id }

    get '/pros/lookup', params
    assert_response(@response, :success)
    assert_equal(orig_contrib_points + bonus_points, @parsed_response['Promo']['ContributedPoints'])

    # Step 4
    params = {
      'promo_id' => @active_promo_id,
      'points' => (bonus_points * -1),
      'moderator_id' => 'App Services',
      'notes' => 'API Test'
    }

    post '/pros/bonus', params
    assert_response(@response, :success)
    transactions << @parsed_response['Bonus']

    # Step 5
    params = {
      'promo_id' => @active_promo_id,
      'include_transaction_history' => 'true'
    }

    get '/pros/lookup', params
    assert_response(@response, :success)
    assert_equal(orig_contrib_points, @parsed_response['Promo']['ContributedPoints'])

    # Step 6
    transactions.each do |transaction|
      assert_includes(@parsed_response['Transactions'], transaction)
    end
  end

  ##
  # AS-7039 | PTA - New endpoint to fetch reviews for moderation
  # AS-7350 | YP4S - Change the moderate/reviews to return reviews for all
  #
  # Steps:
  # Setup: New User, Get Promo, Add User to Promo
  # 1. Get Promo associated categories then get listings
  # 2. User adds reviews for six businesses within the category returned
  # 3. Get reviews for New User for different filter options
  # 4. Get only reviews assigned to Promo
  # 5. Verify response for sorting by source
  def test_moderator_fetch_reviews
    # Setup
    @user = setup_user
    @user2 = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 1
    business_listings = get_promo_listings
    assert(business_listings.length > 1)

    # Step 2
    assign_http(Config['panda']['host'])

    count = 0
    int_xxids = []
    sources = ['CSE','XX3','XXMOBILE','CSE','XX3','XXMOBILE','CSE','XX3','XXMOBILE']
    business_listings.each do |business|
      break if count > 6
      int_xxids << business['Int_Xxid']

      params = {
          'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
          'source' => sources[count],
          'subject' => 'Review made by API',
          'value' => rand(1..5),
          'listing_id' => business['Int_Xxid'],
          'oauth_token' => @user.oauth_token,
          'promo_id' => @active_promo_id
      }

      put '/usr/reviews', params
      assert_response(@response, :success)

      params = {
          'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
          'source' => sources[count],
          'subject' => 'Review made by API',
          'value' => rand(1..5),
          'listing_id' => business['Int_Xxid'],
          'oauth_token' => @user2.oauth_token,
      }

      put '/usr/reviews', params
      assert_response(@response, :success)

      count += 1
    end

    # Step 3
    # Only Promo Reviews check - include_only_promo_reviews
    params = { 'include_only_promo_reviews' => true }

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(10, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert(review['PromoId'], review)
    end

    # Default Check - promo id only
    params['promo_id'] = @active_promo_id

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(10, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(@active_promo_id, review['PromoId'],
                   "Expected the review PromoId to match #{@active_promo_id}: #{review}")
    end

    # Default Check - promo id + author user id
    params['author_user_id'] = @user.id

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(count, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(@user.id, review['AuthorUserId'],
                   "Expected the review AuthorUserId to match #{@user.id}: #{review}")
    end

    # Status check - Approved
    params['status'] = 'approved'

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(0, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(0, review['Suppressed'],
                   "Expected the review Suppressed to match 0: #{review}")
    end

    # Status check - Rejected
    params['status'] = 'rejected'

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(0, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(0, review['Suppressed'],
                   "Expected the review Suppressed to match 0: #{review}")
    end

    # Status check - Assigned
    params['status'] = 'assigned'

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(0, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_nil(review['ModeratorId'],
                   "Expected the review ModeratorId to be unassigned: #{review}")
      assert_equal(0, review['Moderated'],
                   "Expected the review Moderated to match 0: #{review}")
    end

    # Status check - Unassigned
    params['status'] = 'unassigned'

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(count, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_nil(review['ModeratorId'],
                 "Expected the review ModeratorId to be unassigned: #{review}")
      assert_equal(0, review['Moderated'],
                   "Expected the review Moderated to match 0: #{review}")
    end

    # Limit check
    params = {
        'promo_id' => @active_promo_id,
        'h' => 1
    }

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(params['h'], @parsed_response['Reviews'].length, @parsed_response)
    no_offset = @parsed_response['Reviews']

    # Offset check
    params['o'] = 1

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(params['h'], @parsed_response['Reviews'].length, @parsed_response)
    no_offset.each do |review|
      refute_match(review, @parsed_response['Reviews'][0])
    end

    # Int_Xxid check
    int_xxid = int_xxids[(rand(count))]

    params = {
        'promo_id' => @active_promo_id,
        'author_user_id' => @user.id,
        'status' => 'unassigned',
        'int_xxid' => int_xxid,
    }

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(1, @parsed_response['Reviews'].length, @parsed_response)
    assert_equal(int_xxid.to_i, @parsed_response['Reviews'][0]['Int_Xxid'])

    int_xxid = int_xxids[(rand(count))]

    # User Email check
    params = {
        'promo_id' => @active_promo_id,
        'author_email' => @user.email,
        'status' => 'unassigned',
        'int_xxid' => int_xxid,
    }

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(1, @parsed_response['Reviews'].length, @parsed_response)
    assert_equal(int_xxid.to_i, @parsed_response['Reviews'][0]['Int_Xxid'])
    assert_equal(@user.email, @parsed_response['Reviews'][0]['Email'])

    # Step 4
    params = {
        'promo_id' => @active_promo_id,
        'include_total_unmoderated_count' => true, # AS-7229
    }

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert(@parsed_response['TotalUnmoderatedCount'] >= 0)
    assert_equal(10, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(@active_promo_id, review['PromoId'],
                   "Expected the review PromoId to match #{@active_promo_id}: #{review}")
    end

    # Step 5
    # Sorting by source
    params = {
        'include_only_promo_reviews' => true,
        'author_user_id' => @user.id,
        's' => 'source:desc'
    }

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(count, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert(review['PromoId'], review)
      assert(sources.include?(review['Source']),
                     "Expected the review Source to match of the specified sources, #{sources}: #{review}")
    end
    assert_equal('XXMOBILE', @parsed_response['Reviews'].first['Source'])
    assert_equal('CSE', @parsed_response['Reviews'].last['Source'])

    # Step 6
    # Non Promo Review check
    params = {
        'include_only_promo_reviews' => false,
        'author_user_id' => @user2.id,
        's' => 'source:asc'
    }

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(count, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(@user2.id, review['AuthorUserId'],
                   "Expected the review AuthorUserId to match #{@user.id}: #{review}")
      assert(sources.include?(review['Source']),
                   "Expected the review Source to match of the specified sources, #{sources}: #{review}")
    end
    assert_equal('CSE', @parsed_response['Reviews'].first['Source'])
    assert_equal('XXMOBILE', @parsed_response['Reviews'].last['Source'])
  end

  ##
  # AS-7040 | PTA - Assign reviews to a moderator
  #
  # Steps:
  # Setup: New User, Get Promo, Add User to Promo
  # 1. Get Promo associated categories then get listings
  # 2. User adds reviews businesses within the category returned
  # 3. Verify response for assigning a review to the moderator id specified
  def test_assign_moderator_reviews
    # Setup
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 1
    business_listings = get_promo_listings
    assert(business_listings.length > 1)

    # Step 2
    assign_http(Config['panda']['host'])

    count = 0
    business_listings.each do |business|
      break if count > 2

      params = {
          'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
          'source' => 'XX3',
          'subject' => 'Review made by API',
          'value' => rand(1..5),
          'listing_id' => business['Int_Xxid'],
          'oauth_token' => @user.oauth_token,
          'promo_id' => @active_promo_id
      }

      put '/usr/reviews', params
      assert_response(@response, :success)

      count += 1
    end

    # Step 3
    moderator_id = unique_moderator_id

    params = {
        'promo_id' => @active_promo_id,
        'moderator_id' => moderator_id,
        'limit' => 1
    }

    put '/mod/reviews/assign', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(moderator_id, review['ModeratorId'], @parsed_response)
      assert_equal(@active_promo_id, review['PromoId'], @parsed_response)
    end

    params['limit'] = 2

    put '/mod/reviews/assign', params
    assert_response(@response, :success)
    assert_equal(3, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(moderator_id, review['ModeratorId'], @parsed_response)
      assert_equal(@active_promo_id, review['PromoId'], @parsed_response)
    end
  end

  ##
  # AS-7041 | PTA - Assign reviews to a moderator
  #
  # Steps:
  # Setup: New User, Get Promo, Add User to Promo
  # 1. Get Promo associated categories then get listings
  # 2. User adds reviews businesses within the category returned
  # 3. Verify response for assigning a review to the moderator id specified
  # 4. Verify response for moderator rejecting a review
  def test_moderator_rejects_review
    # Setup
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 1
    business_listings = get_promo_listings
    assert(business_listings.length > 1)

    # Step 2
    assign_http(Config['panda']['host'])

    count = 0
    business_listings.each do |business|
      break if count > 2

      params = {
          'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
          'source' => 'XX3',
          'subject' => 'Review made by API',
          'value' => rand(1..5),
          'listing_id' => business['Int_Xxid'],
          'oauth_token' => @user.oauth_token,
          'promo_id' => @active_promo_id
      }

      put '/usr/reviews', params
      assert_response(@response, :success)

      count += 1
    end

    # Step 3
    moderator_id = unique_moderator_id

    params = {
        'promo_id' => @active_promo_id,
        'moderator_id' => moderator_id,
        'limit' => 1
    }

    put '/mod/reviews/assign', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(moderator_id, review['ModeratorId'], @parsed_response)
      assert_equal(@active_promo_id, review['PromoId'], @parsed_response)
    end

    review = @parsed_response['Reviews'].first
    if review['Suppressed'] == 0
      status = 'rejected'
      suppressed_response = 1
    else
      status = 'approved'
      suppressed_response = 0
    end

    params = {
        'id' => review['Id'],
        'status' => status,
        'moderator_id' => moderator_id
    }

    put '/mod/reviews', params
    assert_response(@response, :success)
    assert_equal(moderator_id, @parsed_response['Review']['ModeratorId'], @parsed_response)
    assert_equal(@active_promo_id, @parsed_response['Review']['PromoId'], @parsed_response)
    assert_equal(suppressed_response, @parsed_response['Review']['Suppressed'], @parsed_response)
  end

  ##
  # AS-7199 | PTA: Correctly update review counts & moderated date.
  # AS-7226 | PTA - Review Moderation Tool - Support Adding a Note
  # ~ put '/mod/reviews', params { 'status' => 'approved', 'rejected', not provided }
  #
  # Steps:
  # Setup: New User, Get Promo, Add User to Promo
  # 1. Get Promo associated categories then get listings
  # 2. User adds three+ reviews for six businesses within the category returned
  # 3. Get the baseline promo and review details
  # 4. Moderator rejects, accepts, and provides no status on each review unmoderated
  # 5. Verify updates to Promo and User stats
  def test_updates_to_moderated_reviews_count_and_date
    # Setup
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 1
    business_listings = get_promo_listings
    assert(business_listings.length > 1)

    # Step 2
    assign_http(Config['panda']['host'])

    count = 0
    business_listings.each do |business|
      break if count > 6

      params = {
          'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
          'source' => 'XX3',
          'subject' => 'Review made by API',
          'value' => rand(1..5),
          'listing_id' => business['Int_Xxid'],
          'oauth_token' => @user.oauth_token,
          'promo_id' => @active_promo_id
      }

      put '/usr/reviews', params
      assert_response(@response, :success)

      count += 1
    end

    # Step 3
    get '/pros', {}
    assert_response(@response, :success)
    promo = @parsed_response['Promos'].find { |promo| promo['Code'] == @active_promo }
    refute_nil(promo)

    params = {
        'promo_id' => @active_promo_id,
        'author_user_id' => @user.id
    }

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'])
    assert_equal(count, @parsed_response['Reviews'].length, @parsed_response)
    @parsed_response['Reviews'].each do |review|
      assert_equal(@user.id, review['AuthorUserId'])
      assert_equal(@active_promo_id, review['PromoId'])
      assert_equal(0, review['Suppressed'])
      assert_equal(0, review['Moderated'])
      assert_nil(review['ModeratorId'])
      assert_nil(review['ModeratorNotes'])
      assert_nil(review['ModeratedDate'])
    end

    # Step 4
    moderator_id = unique_moderator_id

    params = {
        'promo_id' => @active_promo_id,
        'moderator_id' => moderator_id
    }

    put '/mod/reviews/assign', params
    assert_response(@response, :success)
    assigned_reviews = @parsed_response['Reviews']
    assigned_reviews.each do |review|
      assert_equal(@active_promo_id, review['PromoId'])
      assert_equal(0, review['Suppressed'])
      assert_equal(0, review['Moderated'])
      assert_equal(moderator_id, review['ModeratorId'])
      assert_nil(review['ModeratorNotes'])
      assert_nil(review['ModeratedDate'])
    end

    params = {
        'id' => assigned_reviews[0]['Id'],
        'status' => 'rejected',
        'moderator_id' => moderator_id,
        'suppress_reason' => 'rejected reason'
    }

    put '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Review'])
    review = @parsed_response['Review']
    assert_equal(@active_promo_id, review['PromoId'])
    assert_equal(1, review['Suppressed'])
    assert_equal(1, review['Moderated'])
    assert_equal(moderator_id, review['ModeratorId'])
    assert_equal(params['suppress_reason'], review['SuppressReason'])
    refute_nil(review['ModeratedDate'])
    assert_equal(DateTime.now.utc.strftime('%y%m%d').to_i, DateTime.parse(review['ModeratedDate']).strftime('%y%m%d').to_i)

    params = {
        'id' => assigned_reviews[1]['Id'],
        'status' => 'approved',
        'moderator_id' => moderator_id,
        'notes' => 'approved notes'
    }

    put '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Review'])
    review = @parsed_response['Review']
    assert_equal(@active_promo_id, review['PromoId'])
    assert_equal(0, review['Suppressed'])
    assert_equal(1, review['Moderated'])
    assert_equal(moderator_id, review['ModeratorId'])
    assert_equal(params['notes'], review['Notes'])
    refute_nil(review['ModeratedDate'])
    assert_equal(DateTime.now.utc.strftime('%y%m%d').to_i, DateTime.parse(review['ModeratedDate']).strftime('%y%m%d').to_i)

    params = {
        'id' => assigned_reviews[2]['Id'],
        'moderator_id' => moderator_id,
        'notes' => 'no status'
    }

    put '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Review'])
    review = @parsed_response['Review']
    assert_equal(@active_promo_id, review['PromoId'])
    assert_equal(0, review['Suppressed'])
    assert_equal(0, review['Moderated'])
    assert_equal(moderator_id, review['ModeratorId'])
    assert_equal(params['notes'], review['Notes'])
    assert_nil(review['ModeratedDate'])

    # Step 5
    get '/pros', {}
    assert_response(@response, :success)
    updated_promo = @parsed_response['Promos'].find { |promo| promo['Code'] == @active_promo }
    refute_nil(updated_promo)
    assert_equal(promo['ReviewCount'], updated_promo['ReviewCount'])
    assert_equal((promo['AcceptedReviewCount'] + 1), updated_promo['AcceptedReviewCount'])
    assert_equal((promo['SuppressedReviewCount'] + 1), updated_promo['SuppressedReviewCount'])
    assert_equal((promo['UnmoderatedReviewCount'] - 2), updated_promo['UnmoderatedReviewCount'])
  end

  ##
  # AS-7221 | Test status GET/POST/PUT/DELETE Promo Messages
  # AS-7277 | Ability to add bulk marketing messages via file upload
  #
  # Steps
  # Setup: Create promo
  # 1. Verify response for POST the message
  # 2. Verify message added via Promo Lookup
  # 3. Verify response for PUT the message
  # 4. Verify message updated via Promo Lookup
  # 5. Verify response for DELETE the message
  # 6. Verify message soft deleted via Promo Lookup
  # 7. Verify response for POST bulk messages to promo
  # Clean-up: Delete created promo
  def test_promo_messages_crud
    # Setup
    params = { 'start_date' => (Time.now - 1.day).to_i }

    create_new_promo(params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo'])
    promo = @parsed_response['Promo']
    assert(promo['Code'], promo)
    assert(promo['Id'], promo)

    moderator_id = "Peter_Parker_#{Common.random_uuid}"
    new_message = "Your friendly neighborhood Spiderman! - #{Common.random_uuid}"
    start_date = (Time.now - 1.day).to_i
    end_date = (Time.now + rand(10..20).day).to_i

    # Step 1
    params = {
        'promo_id' => promo['Id'],
        'moderator_id' => moderator_id,
        'message' => new_message,
        'start_date' => start_date,
        'end_date' => end_date
    }

    post '/pros/messages', params
    assert_response(@response, :success)
    promo_message = @parsed_response['PromoMessage']
    message_id = promo_message['Id']
    assert_equal(new_message, promo_message['Message'])
    assert_equal(start_date, DateTime.parse(promo_message['StartDate']).to_i)
    assert_equal(end_date, DateTime.parse(promo_message['EndDate']).to_i)

    # Step 2
    lookup_params = {
        'promo_id' => promo['Id'],
        'include_messages' => true
    }

    get '/pros/lookup?', lookup_params
    assert_response(@response, :success)
    promo_messages = @parsed_response['Messages']
    message = promo_messages.find { |message| message['Id'] == message_id }
    refute_nil(message)
    assert_equal(new_message, message['Message'])
    assert_equal(start_date, DateTime.parse(message['StartDate']).to_i)
    assert_equal(end_date, DateTime.parse(message['EndDate']).to_i)
    assert_equal('Live', message['Status'])

    # Step 3
    updated_message = "Spiderman! Spiderman! Does Whatever a Spiderman Does! - #{Common.random_uuid}"
    start_date = (Time.now + 5.day).to_i
    end_date = (Time.now + rand(10..20).day).to_i

    update_params = {
        'promo_id' => promo['Id'],
        'moderator_id' => moderator_id,
        'message_id' => message_id,
        'message' => updated_message,
        'start_date' => start_date,
        'end_date' => end_date
    }

    put '/pros/messages', update_params
    assert_response(@response, :success)
    updated_promo_message = @parsed_response['PromoMessage']
    assert_equal(message_id, updated_promo_message['Id'])
    assert_equal(updated_message, updated_promo_message['Message'])
    assert_equal(start_date, DateTime.parse(updated_promo_message['StartDate']).to_i)
    assert_equal(end_date, DateTime.parse(updated_promo_message['EndDate']).to_i)

    # Step 4
    get '/pros/lookup?', lookup_params
    assert_response(@response, :success)
    promo_messages = @parsed_response['Messages']
    message = promo_messages.find { |message| message['Id'] == message_id }
    refute_nil(message)
    assert_equal(updated_message, message['Message'])
    assert_equal(start_date, DateTime.parse(message['StartDate']).to_i)
    assert_equal(end_date, DateTime.parse(message['EndDate']).to_i)
    assert_equal('Future', message['Status'])

    # Step 5
    delete_params = {
        'promo_id' => promo['Id'],
        'moderator_id' => moderator_id,
        'message_id' => message_id
    }

    delete '/pros/messages', delete_params
    assert_response(@response, :success)

    # Step 6
    get '/pros/lookup?', lookup_params
    assert_response(@response, :success)
    promo_messages = @parsed_response['Messages']
    message = promo_messages.find { |message| message['Id'] == message_id }
    refute_nil(message)
    assert_equal(updated_message, message['Message'])
    assert_equal(start_date, DateTime.parse(message['StartDate']).to_i)
    assert_equal(end_date, DateTime.parse(message['EndDate']).to_i)
    assert_equal('Deleted', message['Status'])

    # Step 7
    start_date = (Time.now - 1.day).to_i
    end_date = (Time.now + rand(10..20).day).to_i

    new_promo_messages = [
        {
            'promo_id' => promo['Id'],
            'moderator_id' => moderator_id,
            'message' => "One scientific mishap, and hours later I'm sewing a costume.",
            'start_date' => start_date,
            'end_date' => end_date
        },
        {
            'promo_id' => promo['Id'],
            'moderator_id' => moderator_id,
            'message' => "You say you don't want the responsibility? Guess what? People like us...we don't get a choice.",
            'start_date' => start_date,
            'end_date' => end_date
        },
        {
            'promo_id' => promo['Id'],
            'moderator_id' => moderator_id,
            'message' => "Holy Cow! It's really him -- The Green Goblin lives again! ",
            'start_date' => start_date,
            'end_date' => end_date
        }
    ]

    params = {
        'promo_messages' => new_promo_messages
    }

    post '/pros/messages/multi', params
    assert_response(@response, :success)
    assert(@parsed_response['PromoMessages'])
    promo_messages = @parsed_response['PromoMessages']
    promo_messages.each do |promo_message|
      assert(promo_message['Id'])
      assert_equal(promo['Id'], promo_message['PromoId'])
      assert(new_promo_messages.find { |pm| pm['message'] == promo_message['Message'] })
      assert_equal(start_date, DateTime.parse(promo_message['StartDate']).to_i)
      assert_equal(end_date, DateTime.parse(promo_message['EndDate']).to_i)
      assert_equal(moderator_id, promo_message['ModeratorId'])
      assert_equal(0, promo_message['Deleted'])
      assert_equal('Live', promo_message['Status'])
    end
  end

  ##
  # AS-7230 | PTA - Review Moderation Tool - Support the Ability to Bulk "Approve/Reject" Reviews
  #
  # Steps:
  # Setup: New User, Get Promo, Add User to Promo
  # 1. Get Promo associated categories then get listings
  # 2. User adds reviews for six businesses within the category returned
  # 3. Verify response for approving batch of reviews
  # 4. Verify response for rejecting batch of reviews
  def test_moderator_fetch_multi_batch_reviews
    # Setup
    @user = setup_user

    assign_http(Config['turtle']['host'])

    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }
    params = { 'promo_id' => @active_promo_id }
    params['promo_team'] = @promo['TeamNames'].sample unless @promo['TeamNames'].empty?

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 1
    business_listings = get_promo_listings
    assert(business_listings.length > 1)

    # Step 2
    assign_http(Config['panda']['host'])

    count = 0
    ids = []
    business_listings.each do |business|
      break if count >= 6

      params = {
          'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
          'source' => 'XX3',
          'subject' => 'Review made by API',
          'value' => rand(1..5),
          'listing_id' => business['Int_Xxid'],
          'oauth_token' => @user.oauth_token,
          'promo_id' => @active_promo_id
      }

      put '/usr/reviews', params
      assert_response(@response, :success)
      ids << @parsed_response['RatingID']

      count += 1
    end

    rating_ids = ids.each_slice(3).to_a

    # Step 3
    moderator_id = unique_moderator_id

    params = {
        'ids' => rating_ids[0],
        'promo_id' => @active_promo_id,
        'moderator_id' => moderator_id,
        'status' => 'approved',
        'notes' => 'excellent reviews!'
    }

    put '/mod/reviews/multi', params
    assert_response(@response, :success)
    reviews = @parsed_response['Reviews']

    rating_ids[0].each do |rating_id|
      review = reviews.find {|rev| rev['Id'] == rating_id}
      assert_equal(0, review['Suppressed'])
      assert_equal(1, review['Moderated'])
      assert_equal(moderator_id, review['ModeratorId'])
      assert_equal(@active_promo_id, review['PromoId'])
      assert_equal(params['notes'], review['Notes'])
      assert_nil(review['SuppressReason'])
    end

    # Step 4
    params = {
        'ids' => rating_ids[1],
        'promo_id' => @active_promo_id,
        'moderator_id' => moderator_id,
        'status' => 'rejected',
        'suppress_reason' => 'terrible reviews!'
    }

    put '/mod/reviews/multi', params
    assert_response(@response, :success)
    reviews = @parsed_response['Reviews']

    rating_ids[1].each do |rating_id|
      review = reviews.find {|rev| rev['Id'] == rating_id}
      assert_equal(1, review['Suppressed'])
      assert_equal(1, review['Moderated'])
      assert_equal(moderator_id, review['ModeratorId'])
      assert_equal(@active_promo_id, review['PromoId'])
      assert_equal(params['suppress_reason'], review['SuppressReason'])
      assert_nil(review['Notes'])
    end
  end

  ##
  # AS-7299 | YP4S - Return the avatar sha for the review moderation tool
  # AS-7312 | YP4S tools support - Add email_address to moderator/reviews endpoint response
  # ~ ypastest@gmail has existing profile images for FB & G+
  #
  # Steps:
  # Setup: Login existing user, get avatar_urls, create new promo
  # 1. Add existing user to new promo
  # 2. Get business listings for random business to review
  # 3. Add review for this user to that business
  # 4. Retrieve review for this user
  # Clean-up: Delete Promo
  def test_display_avatar_url_in_review_moderation_tool
    # Setup
    email = 'ypastest@gmail.com'

    @users = []
    @users << login_existing_user({ 'email' => email })
    @users << setup_user

    delete_all_reviews_for_user_by_id(@users[0].id)

    get_user_info(@users[0].oauth_token)
    assert_response(@response, :success)
    assert(@parsed_response['accounts'])
    assert_equal(2, @parsed_response['accounts'].length)

    avatar_urls = []
    @parsed_response['accounts'].each do |account|
      avatar_urls << account['avatar_url'] if account['avatar_url']
    end
    refute_empty(avatar_urls)

    promo_name = "promo_name_#{Common.random_uuid}"
    params = {
        'start_date' => (Time.now - 1.day).to_i,
        'name' => promo_name
    }

    create_new_promo(params)
    assert_response(@response, :success)
    assert(@parsed_response['Promo'])
    promo = @parsed_response['Promo']
    assert(promo['Code'], promo)
    assert(promo['Id'], promo)
    assert(promo['Name'], promo)

    # Step 1
    assign_http(Config['turtle']['host'])
    @users.each do |user|
      headers = { 'Authorization' => "Bearer #{user.oauth_token}" }
      params = { 'promo_id' => promo['Id'] }
      params['promo_team'] = promo['TeamNames'].sample

      put '/usr', params, headers
      assert_response(@response, :success)
    end

    # Step 2
    business_listings = get_promo_listings.shuffle!
    assert(business_listings.length > 1)
    business = business_listings.sample

    search_opts = { 'promo_id' => promo['Id'] }

    get_consumer_business_resp(business['Int_Xxid'], search_opts)
    assert_response(@response, :success)
    business = @parsed_response['Business']

    # Step 3
    assign_http(Config['panda']['host'])

    rating_id = nil
    review_avatar_url = nil

    @users.each do |user|
      params = {
          'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
          'source' => 'XX3',
          'subject' => 'Review made by API',
          'value' => rand(1..5),
          'listing_id' => business['Int_Xxid'],
          'oauth_token' => user.oauth_token,
          'promo_id' => promo['Id']
      }

      put '/usr/reviews', params
      assert_response(@response, :success)

      if user.email == email
        rating_id = @parsed_response['RatingID']
        review_avatar_url = @parsed_response['Rating']['UserInfo']['User']['AvatarURL']
      end
    end

    assert(rating_id)
    assert(review_avatar_url)
    assert(avatar_urls.find { |url| url == review_avatar_url })

    # Step 4
    params = {
        'promo_id' => promo['Id'],
        'author_user_id' => @users[0].id,
        'int_xxid' => business['Int_Xxid'],
    }

    get '/mod/reviews', params
    assert_response(@response, :success)
    assert(@parsed_response['Reviews'][0])
    review = @parsed_response['Reviews'][0]
    assert_equal(rating_id, review['Id'], review)
    assert_equal(@users[0].id, review['AuthorUserId'], review)
    assert_equal(review_avatar_url, review['AvatarUrl'], review)
    assert_equal(email, review['Email'], review)
    assert_equal(promo_name, review['PromoName'], review)
    assert_equal(1, @parsed_response['TotalCount'])
  end

  ##
  # AS-7271 | YP4S- Ability to add bulk Add-on Points via file upload
  # AS-7272 | YP4B- Ability to bulk soft delete add-on points
  # AS-7329 | YP4S Tools support - Tools Uber cat support
  #
  # Steps:
  # Setup: Create new promos
  # 1. Verify response for adding bulk upload for addon points to promo
  # 2. Verify response for bulk soft delete for addon points to promo
  # 3. Verify response for single soft delete for addon points to promo
  # 4. Verify response for adding single addon points to promo
  # 5. Verify response for updating single addon points to promo
  # 6. Verify response for GET addon points to promo
  # Clean-up Delete the created promos
  def test_promo_addon_points
    # Setup
    assign_http(Config['panda']['host'])

    promos = []
    params = { 'start_date' => (Time.now - 1.day).to_i }

    2.times do
      create_new_promo(params)
      assert_response(@response, :success)
      assert(@parsed_response['Promo'])
      promo = @parsed_response['Promo']
      assert(promo['Code'], promo)
      assert(promo['Name'], promo)
      assert(promo['Id'], promo)
      assert(promo['DefaultAttributes'], promo)
      assert(promo['TeamNames'], promo)

      promos << promo
    end

    # Step 1
    start_date = (Time.now - 1.day).to_i
    end_date = (Time.now + rand(10..20).day).to_i
    moderator_id = unique_moderator_id
    uber_cat = 'uber cat string'

    params = {
        'promo_addon_points' => [
            {
                'promo_id' => promos[0]['Id'],
                'review_addon_points' => 10,
                'photo_addon_points' => 20,
                'group_heading_code' => 1111111,
                'heading_code' => 8002304,
                'start_date' => start_date,
                'end_date' => end_date,
                'moderator_id' => moderator_id,
                'uber_cat' => uber_cat
            },
            {
                'promo_id' => promos[0]['Id'],
                'review_addon_points' => 20,
                'photo_addon_points' => 30,
                'heading_code' => 8004199,
                'start_date' => start_date,
                'end_date' => end_date,
                'moderator_id' => moderator_id,
                'uber_cat' => uber_cat
            },
            {
                'promo_id' => promos[1]['Id'],
                'review_addon_points' => 40,
                'photo_addon_points' => 50,
                'heading_code' => 8002304,
                'start_date' => start_date,
                'end_date' => end_date,
                'moderator_id' => moderator_id,
                'uber_cat' => uber_cat
            },
            {
                'promo_id' => promos[1]['Id'],
                'review_addon_points' => 60,
                'photo_addon_points' => 70,
                'group_heading_code' => 1111111,
                'heading_code' => 8004199,
                'start_date' => start_date,
                'end_date' => end_date,
                'moderator_id' => moderator_id,
                'uber_cat' => uber_cat
            }
        ]
    }

    post '/pros/addon_points/multi', params
    assert_response(@response, :success)
    assert(@parsed_response['PromoAddonPoints'])

    addon_point_ids = []
    @parsed_response['PromoAddonPoints'].each do |addon_points|
      param_addon_points = params['promo_addon_points'].find { |h|
        h['heading_code'].to_s == addon_points['HeadingCode'] && h['promo_id'] == addon_points['PromoId'] }
      if param_addon_points
        assert(addon_points['Id'])
        addon_point_ids << addon_points['Id']
        assert_equal(param_addon_points['promo_id'], addon_points['PromoId'])
        assert_equal(param_addon_points['review_addon_points'], addon_points['ReviewAddonPoints'])
        assert_equal(param_addon_points['photo_addon_points'], addon_points['PhotoAddonPoints'])
        assert_equal(param_addon_points['heading_code'].to_s, addon_points['HeadingCode'])
        assert_equal(param_addon_points['group_heading_code'].to_s, addon_points['GroupHeadingCode']) if addon_points['GroupHeadingCode']
        assert_equal(param_addon_points['start_date'], DateTime.parse(addon_points['StartDate']).to_i)
        assert_equal(param_addon_points['end_date'], DateTime.parse(addon_points['EndDate']).to_i)
        assert_equal(param_addon_points['moderator_id'], addon_points['ModeratorId'])
        assert_equal(0, addon_points['Deleted'])
      end
    end

    # Step 2
    addon_point_ids.shuffle!
    multi_delete_addon_point_ids = addon_point_ids.shift(2)

    delete_params = {
        'addon_points_ids' => multi_delete_addon_point_ids,
        'moderator_id' => moderator_id
    }

    delete '/pros/addon_points/multi', delete_params
    assert_response(@response, :success)
    assert(@parsed_response['PromoAddonPoints'])
    @parsed_response['PromoAddonPoints'].each do |addon_points|
      param_addon_points = params['promo_addon_points'].find { |h|
        h['heading_code'].to_s == addon_points['HeadingCode'] && h['promo_id'] == addon_points['PromoId'] }
      if param_addon_points && multi_delete_addon_point_ids.include?(addon_points['Id'])
        assert_equal(param_addon_points['promo_id'], addon_points['PromoId'])
        assert_equal(param_addon_points['review_addon_points'], addon_points['ReviewAddonPoints'])
        assert_equal(param_addon_points['photo_addon_points'], addon_points['PhotoAddonPoints'])
        assert_equal(param_addon_points['heading_code'].to_s, addon_points['HeadingCode'])
        assert_equal(param_addon_points['group_heading_code'].to_s, addon_points['GroupHeadingCode']) if addon_points['GroupHeadingCode']
        assert_equal(param_addon_points['start_date'], DateTime.parse(addon_points['StartDate']).to_i)
        assert_equal(param_addon_points['end_date'], DateTime.parse(addon_points['EndDate']).to_i)
        assert_equal(param_addon_points['moderator_id'], addon_points['ModeratorId'])
        assert_equal(1, addon_points['Deleted'])
      end
    end

    # Step 3
    single_delete_addon_point_id = addon_point_ids.sample

    delete_params = {
        'addon_points_id' => single_delete_addon_point_id,
        'moderator_id' => moderator_id
    }

    delete '/pros/addon_points', delete_params
    assert_response(@response, :success)
    assert(@parsed_response['PromoAddonPoints'])
    deleted_addon_points = @parsed_response['PromoAddonPoints']
    param_addon_points = params['promo_addon_points'].find { |h|
      h['heading_code'].to_s == deleted_addon_points['HeadingCode'] && h['promo_id'] == deleted_addon_points['PromoId'] }
    if param_addon_points && single_delete_addon_point_id == deleted_addon_points['Id']
      assert_equal(param_addon_points['promo_id'], deleted_addon_points['PromoId'])
      assert_equal(param_addon_points['review_addon_points'], deleted_addon_points['ReviewAddonPoints'])
      assert_equal(param_addon_points['photo_addon_points'], deleted_addon_points['PhotoAddonPoints'])
      assert_equal(param_addon_points['heading_code'].to_s, deleted_addon_points['HeadingCode'])
      assert_equal(param_addon_points['group_heading_code'].to_s, deleted_addon_points['GroupHeadingCode']) if deleted_addon_points['GroupHeadingCode']
      assert_equal(param_addon_points['start_date'], DateTime.parse(deleted_addon_points['StartDate']).to_i)
      assert_equal(param_addon_points['end_date'], DateTime.parse(deleted_addon_points['EndDate']).to_i)
      assert_equal(param_addon_points['moderator_id'], deleted_addon_points['ModeratorId'])
      assert_equal(1, deleted_addon_points['Deleted'])
    end

    # Step 4
    params = {
        'promo_id' => promos[0]['Id'],
        'review_addon_points' => 100,
        'photo_addon_points' => 200,
        'group_heading_code' => 2222222,
        'heading_code' => 8002305,
        'start_date' => start_date,
        'end_date' => end_date,
        'moderator_id' => moderator_id,
    }

    post '/pros/addon_points', params
    assert_response(@response, :success)
    assert(@parsed_response['PromoAddonPoints'])
    addon_points = @parsed_response['PromoAddonPoints']
    assert(addon_points['Id'])
    assert_equal(params['promo_id'], addon_points['PromoId'])
    assert_equal(params['review_addon_points'], addon_points['ReviewAddonPoints'])
    assert_equal(params['photo_addon_points'], addon_points['PhotoAddonPoints'])
    assert_equal(params['heading_code'].to_s, addon_points['HeadingCode'])
    assert_equal(params['group_heading_code'].to_s, addon_points['GroupHeadingCode'])
    assert_equal(params['start_date'], DateTime.parse(addon_points['StartDate']).to_i)
    assert_equal(params['end_date'], DateTime.parse(addon_points['EndDate']).to_i)
    assert_equal(params['moderator_id'], addon_points['ModeratorId'])
    assert_equal(0, addon_points['Deleted'])

    # Step 5
    update_params = {
        'promo_id' => promos[0]['Id'],
        'addon_points_id' => addon_points['Id'],
        'review_addon_points' => 50,
        'photo_addon_points' => 100,
        'uber_cat' => uber_cat
    }

    put '/pros/addon_points', update_params
    assert_response(@response, :success)
    assert(@parsed_response['PromoAddonPoints'])
    updated_addon_points = @parsed_response['PromoAddonPoints']
    assert_equal(params['promo_id'], updated_addon_points['PromoId'])
    assert_equal(update_params['review_addon_points'], updated_addon_points['ReviewAddonPoints'])
    assert_equal(update_params['photo_addon_points'], updated_addon_points['PhotoAddonPoints'])
    assert_equal(params['heading_code'].to_s, updated_addon_points['HeadingCode'])
    assert_equal(params['group_heading_code'].to_s, updated_addon_points['GroupHeadingCode'])
    assert_equal(params['start_date'], DateTime.parse(updated_addon_points['StartDate']).to_i)
    assert_equal(params['end_date'], DateTime.parse(updated_addon_points['EndDate']).to_i)
    assert_equal(update_params['uber_cat'], updated_addon_points['UberCat'])
    assert_equal(params['moderator_id'], updated_addon_points['ModeratorId'])
    assert_equal(0, updated_addon_points['Deleted'])

    # Step 6
    addon_points_response = []

    promos.each do |promo|
      params = { 'promo_id' => promo['Id'] }

      get '/pros/addon_points', params
      assert_response(@response, :success)
      assert(@parsed_response['PromoAddonPoints'])
      @parsed_response['PromoAddonPoints'].each do |addon_points|
        addon_points_response << addon_points unless addon_points.blank?
      end
    end
    refute_empty(addon_points_response)
    assert_equal(5, addon_points_response.length)
  end

  ##
  # AS-7319 | Support bulk assignment (marketing message, addon-points) promos
  #
  # Steps
  # Setup: Create promo, add points, setup parameters
  # 1. Verify response posting to endpoint for all options
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

    moderator_id = unique_moderator_id
    start_date = (Time.now - 1.day).to_i
    end_date = (Time.now + rand(10..20).day).to_i

    multipliers = []
    addon_points = []
    marketing_messages = []
    promo_points.each do |points_group|
      if points_group['HeadingCode']
        multipliers << {
            'promo_id' => promo['Id'],
            'moderator_id' => moderator_id,
            'start_date' => start_date,
            'end_date' => end_date,
            'review_multiplier' => rand(2..5),
            'photo_multiplier' => rand(2..5),
            'heading_code' => points_group['HeadingCode'],
            'heading_text' => points_group['HeadingText']
        }

        addon_points << {
            'promo_id' => promo['Id'],
            'review_addon_points' => rand(10..20),
            'photo_addon_points' => rand(10..20),
            'heading_code' => points_group['HeadingCode'],
            'start_date' => start_date,
            'end_date' => end_date,
            'moderator_id' => moderator_id,
        }

        marketing_messages << {
            'promo_id' => promo['Id'],
            'moderator_id' => moderator_id,
            'message' => "Marketing_Message_#{Common.random_uuid}",
            'start_date' => start_date,
            'end_date' => end_date,
        }
      end
    end
    refute_empty(multipliers)
    refute_empty(addon_points)
    refute_empty(marketing_messages)

    # Step 1
    params = {
        'multipliers' => multipliers,
        'addon_points' => addon_points,
        'marketing_messages' => marketing_messages
    }

    post '/pros/resources/multi', params
    assert_response(@response, :success)
    refute_empty(@parsed_response['Multipliers'])
    @parsed_response['Multipliers'].each do |multiplier|
      assert(multiplier['Id'], multiplier)
      assert_equal(promo['Id'], multiplier['PromoId'], multiplier)
      assert_equal(moderator_id, multiplier['ModeratorId'], multiplier)
      check = multipliers.find { |m| m['heading_code'] == multiplier['HeadingCode'] }
      assert_equal(start_date, DateTime.parse(multiplier['StartDate']).to_i, multiplier)
      assert_equal(end_date, DateTime.parse(multiplier['EndDate']).to_i, multiplier)
      assert_equal(0, multiplier['Deleted'], multiplier)
      assert_equal('Live', multiplier['Status'], multiplier)
      if check
        assert_equal(check['HeadingText'], multiplier['heading_text'], multiplier)
        assert_equal(check['review_multiplier'], multiplier['ReviewMultiplier'], multiplier)
        assert_equal(check['photo_multiplier'], multiplier['PhotoMultiplier'], multiplier)
      end
    end

    refute_empty(@parsed_response['AddonPoints'])
    @parsed_response['AddonPoints'].each do |addon|
      assert(addon['Id'], addon)
      assert_equal(promo['Id'], addon['PromoId'], addon)
      assert_equal(moderator_id, addon['ModeratorId'], addon)
      assert_equal(start_date, DateTime.parse(addon['StartDate']).to_i, addon)
      assert_equal(end_date, DateTime.parse(addon['EndDate']).to_i, addon)
      assert_equal(0, addon['Deleted'], addon)
      assert_equal('Live', addon['Status'], addon)
      check = addon_points.find { |ap| ap['heading_code'] == addon['HeadingCode'] }
      if check
        assert_equal(check['review_addon_points'], addon['ReviewAddonPoints'], addon)
        assert_equal(check['photo_addon_points'], addon['PhotoAddonPoints'], addon)
      end
    end

    refute_empty(@parsed_response['MarketingMessages'])
    @parsed_response['MarketingMessages'].each do |message|
      assert(message['Id'], message)
      assert_equal(promo['Id'], message['PromoId'], message)
      assert_equal(moderator_id, message['ModeratorId'], message)
      assert_match('Marketing_Message_', message['Message'], message)
      assert_equal(start_date, DateTime.parse(message['StartDate']).to_i, message)
      assert_equal(end_date, DateTime.parse(message['EndDate']).to_i, message)
      assert_equal(0, message['Deleted'], message)
      assert_equal('Live', message['Status'], message)
    end
  end
end
