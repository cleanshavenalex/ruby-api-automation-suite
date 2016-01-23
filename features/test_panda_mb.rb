require './init'
require 'base64'

class TestPandaMB < APITest
  def setup
    assign_http(Config["panda"]["host"])
    @user = TurtleUser.new
  end

  ##
  # :call-seq: TestCase: Search by a Visitor (Not Logged In)
  #
  # Steps:
  # 1. A visitor searches for something
  # 2. Search should show up in the visitor's my book
  def test_add_and_get_search_for_visitor
    # Step 1
    opts = {
        'record_history' => 'true',
        'vrid' => @user.vrid
    }

    get_consumer_search_resp('pizza', 'glendale', opts)
    assert_response(@response, :success)

    # Step 2
    params = { 'vrid' => @user.vrid }

    get '/mb/searches', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Searches'].size, @response.body)
  end

  ##
  # :call-seq: TestCase: Search by a User with access token (Logged In)
  #
  # Steps:
  # 1. A visitor signs up and becomes a user
  # 2. User searches for something
  # 3. Search should show up in user's my book
  # 4. Search should NOT show up in visitor's my book
  def test_add_and_get_search_for_user
    # Step 1
    @user = setup_user

    # Step 2
    opts = {
        'record_history' => 'true',
        'vrid' => @user.vrid,
        'oauth_token' => @user.oauth_token
    }

    get_consumer_search_resp('pizza', 'glendale', opts)
    assert_response(@response, :success)

    # Step 3
    params = {
        'oauth_token' => @user.oauth_token
    }

    get '/mb/searches', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Searches'].size, @response.body)

    # Step 4
    params = { 'vrid' => @user.vrid }

    get '/mb/searches', params
    assert_response(@response, :success)
    assert_equal(0, @parsed_response['Searches'].size, @response.body)
  end

  ##
  # :call-seq: TestCase: Visitor shorttcut merges with user on Sign up
  #
  # Steps:
  # 1. A visitor adds a shortcut to my book
  # 2. Visitor should have a shortcut in my book
  # 3. Visitor signs up and becomes a user
  # 4. User should have a shortcut without adding it
  # 5. Visitor should not have a shortcut in my book anymore
  def test_merge_with_new_user
    # Step 1
    params = {
        'type' => { 'shortcuts' => ['gas'] },
        'vrid' => @user.vrid
    }

    post '/mb/preferences', params
    assert_response(@response, :success)

    # Step 2
    params['type'] = 'shortcuts'

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Shortcuts'].size, @response.body)
    assert_equal('gas', @parsed_response['Shortcuts'].first['Name'])

    # Step 3
    @user = setup_user({'email' => @user.email})

    # Step 4
    params['oauth_token'] = @user.oauth_token

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response['Shortcuts'].size)
    assert_equal('gas', @parsed_response['Shortcuts'].first['Name'])

    # Step 5
    params.delete('oauth_token')

    get '/mb/preferences', params
    assert_response(@response, :success)
    assert_equal(0, @parsed_response['Shortcuts'].size, @response.body)
  end

  ##
  # Visitor adds a note to a business
  #
  # Steps:
  # 1. Post note
  # 2. Get notes for user
  def test_visitor_adds_note_and_retrieves_all_notes
    # Step 1
    params = {
        'vrid' => @user.vrid,
        'note' => 'i am awesome',
        'int_xxid' => 9590059
    }

    post '/mb/notes', params
    assert_response(@response, :success)

    # Step 2
    params = { 'vrid' => @user.vrid }

    get '/mb/notes', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response.size, @response.body)
    assert_equal('i am awesome', @parsed_response.first['Notes'])
  end

  ##
  # Steps:
  # 1. Visitor adds a bunch of stuff to my book
  # 2. Visitor should only have calls, clicks and listings in history
  # 3. Visitor deletes activities
  # 4. Visitor should have nothing in history
  def test_visitor_delete_activites_deletes_everything
    # Step 1
    params = {
        'vrid' => @user.vrid,
        'coupons' => 'id-of-an-awesome-coupon',
        'int_xxid' => '12345'
    }

    post '/mb/coupons', params
    assert_response(@response, :success)

    params = {
        'vrid' => @user.vrid,
        'calls' => '1234567890',
        'int_xxid' => '12345'
    }

    post '/mb/calls', params
    assert_response(@response, :success)

    params = {
        'vrid' => @user.vrid,
        'c' => 'food',
        'int_xxid' => '12345'
    }

    post '/mb/businesses', params
    assert_response(@response, :success)

    params = {
        'vrid' => @user.vrid,
        'note' => 'rawr! this is a note of some sort!',
        'int_xxid' => '12345'
    }

    post '/mb/notes', params
    assert_response(@response, :success)

    opts = {
        'record_history' => 'true',
        'vrid' => @user.vrid
    }

    get_consumer_search_resp('pizza', 'glendale', opts)
    assert_response(@response, :success)

    params = {
        'int_xxid' => '12345',
        'app_id' => 'WEB',
        'vrid' => @user.vrid,
        'record_history' => 'true'
    }

    get '/cons/business', params
    assert_response(@response, :success)

    # Step 2
    params = {
        'vrid' => @user.vrid,
        'type' => 'businesses'
    }

    get '/mb/activities', params
    assert_response(@response, :success)

    expected_activites = %w[call click listing]
    actual_activities = @parsed_response['Activities'].map { |activity| activity['Type'] }
    assert_equal(expected_activites.sort, actual_activities.sort)

    # Step 3
    params = { 'vrid' => @user.vrid }

    delete '/mb/activities', params
    assert_response(@response, :success)

    #Step 4
    params['type'] = 'businesses'

    get '/mb/activities', params
    assert_response(@response, :success)

    expected_activites = []
    actual_activities = @parsed_response['Activities'].map { |activity| activity['Type'] }
    assert_equal(expected_activites.sort, actual_activities.sort)
  end

  ##
  # Visitor adds a listings to my book and paginates through them
  #
  # Steps:
  # 1. Visitor adds 5 listings to my book
  # 2. Visitor requests 2 listings and should see 2 listings with a total count of 5
  # 3. Visitor requests 2 listings with offset 4 and should see 1 listings with a total count of 5
  # 4. Visitor requests 2 listings while sorting by name and should see 2 listings with a total count of 5
  def test_visitor_paginates_through_its_businesses
    # Step 1
    get_consumer_search_resp('pizza', 'glendale, ca')
    assert_response(@response, :success)

    int_xxids = @parsed_response['SearchResult']['BusinessListings'][0..4].map { |business| business['Int_Xxid'] }

    params = {
        'vrid' => @user.vrid,
        'c' => 'food',
    }

    int_xxids.each do |int_xxid|
      params['int_xxid'] = int_xxid

      post '/mb/businesses', params
      assert_response(@response, :success)
    end

    # Step 2
    params = {
        'h' => '2',
        'o' => '0',
        'vrid' => @user.vrid
    }

    get '/mb/businesses', params
    assert_response(@response, :success)

    businesses = @parsed_response['Businesses']
    assert_equal(2, businesses.size)
    assert_equal(5, @parsed_response['TotalCount'])

    # Step 3
    params['o'] = '4'

    get '/mb/businesses', params
    assert_response(@response, :success)

    businesses = @parsed_response['Businesses']
    assert_equal(1, businesses.size)
    assert_equal(5, @parsed_response['TotalCount'])

    # Step 4
    params['o'] = '0'
    params['s'] = 'name'

    get '/mb/businesses', params
    assert_response(@response, :success)

    businesses = @parsed_response['Businesses']
    assert_equal(2, businesses.size)
    assert_equal(5, @parsed_response['TotalCount'])
  end

  ##
  # Visitor adds 2 notes to a business and retrieves with int_xxid filter
  #
  # Steps:
  # 1. Post 2 notes
  # 2. Get notes for visitor with int_xxid filter
  def test_visitor_adds_note_and_retrieves_note_by_int_xxid
    # Step 1
    params = {
        'vrid' => @user.vrid,
        'note' => 'i am awesome',
        'int_xxid' => 9590059
    }

    post '/mb/notes', params
    assert_response(@response, :success)

    params['int_xxid'] = 9590060

    post '/mb/notes', params
    assert_response(@response, :success)

    # Step 2
    params = {
        'vrid' => @user.vrid,
        'int_xxid' => 9590059
    }

    get '/mb/notes', params
    assert_response(@response, :success)
    assert_equal(1, @parsed_response.size, @response.body)
    assert_equal('i am awesome', @parsed_response.first['Notes'])

  end

  ##
  # Visitor adds a "click" (view mip) and should be in activities.
  def test_consumer_business_click_for_visitor
    params = {
        'int_xxid' => 467152316, #portos int_xxid
        'app_id' => 'WEB',
        'vrid' => @user.vrid
    }

    get '/cons/business', params
    assert_response(@response, :success)

    params = {
        'vrid' => @user.vrid,
        'type' => 'businesses'
    }

    get '/mb/activities', params
    assert_response(@response, :success)
    assert_equal(467152316, @parsed_response['Activities'].first['Int_Xxid'])
    assert_equal('click', @parsed_response['Activities'].first['Type'])
  end

  ##
  # Steps:
  # 1. A visitor signs up and becomes a user on the 3.10 application.
  # 2. User adds a few businesses and coupons.
  # 3. User upgrades to mobile 4.x and the app uploads all of the saved data.
  # 4. User should have matching data in my book now.
  def test_3_10_to_4_x_upgrade_for_user
    # Step 1
    @user = setup_user

    # Step 2
    uber_cat = 'all'

    params = {
        'app_id' => 'WEB',
        'vrid' => @user.vrid,
        'ptid' => 'www.xx.com',
        'uc' => [uber_cat],
        'sponsored_results' => 0,
        'lat' => 34.1559416055679,
        'lon' => -118.256176114082,
        'f' => ['coupon_flag:Y']
    }

    get '/listings', params
    assert_response(@response, :success)

    listings = @parsed_response['SearchResult']['BusinessListings']

    ## There's no good way to simulate a user adding stuff on the 3.10 application
    ## from Panda's point of view so we'll just store the stuff in a variable for now
    saved_data = []

    if listings.first.nil?
      assert(listings.first, "No listing returned for : #{params['uc']} ")
    else
      3.times do |i|
        saved_data << {
            'type' => 'listing',
            'int_xxid' => listings[i]['Int_Xxid'],
            'timestamp' => (Time.now.to_f*1000).to_i
        }
      end
    end

    listing_with_coupons = listings.find { |listing| listing['Coupons'] && !listing['Coupons'].empty? }
    listing_with_coupons['Coupons'].each do |coupon|
      saved_data << {
          'type' => 'coupon',
          'int_xxid' => listing_with_coupons['Int_Xxid'],
          'coupon_id' => coupon['CouponId'],
          'timestamp' => (Time.now.to_f*1000).to_i
      }
    end

    # Step 3
    params = {
        'oauth_token' => @user.oauth_token
    }

    put_with_json '/mb/upload_coupons_or_businesses', params, saved_data
    assert_response(@response, :success)

    # Step 4
    params = { 'oauth_token' => @user.oauth_token }

    get '/mb/businesses', params
    assert_response(@response, :success)
    assert_equal(3, @parsed_response['Businesses'].size, @response.body)

    get '/mb/coupons', params
    assert_response(@response, :success)
    assert_equal(listing_with_coupons['Coupons'].count, @parsed_response['Coupons'].size, @response.body)
  end

  ##
  # Steps:
  # 1. A visitor is on mobile 3.10 and adds a few businesses and coupons
  # 2. A visitor upgrades from mobile 3.10 to mobile 4.x with coupons and businesses saved
  # 3. Visitor should have matching data in my book
  # 4. Visitor signs up and becomes a user
  # 5. User should have the coupons and businesses merged in
  # 6. Visitor should not have the coupons and businesses anymore
  def test_3_10_to_4_x_upgrade_for_visitor
    # Step 1
    uber_cat = 'all'

    params = {
        'app_id' => 'WEB',
        'vrid' => @user.vrid,
        'ptid' => 'www.xx.com',
        'uc' => [uber_cat],
        'sponsored_results' => 0,
        'lat' => 34.1559416055679,
        'lon' => -118.256176114082,
        'f' => ['coupon_flag:Y']
    }

    get '/listings', params
    assert_response(@response, :success)
    listings = @parsed_response['SearchResult']['BusinessListings']

    ## There's no good way to simulate a user adding stuff on the 3.10 application
    ## from Panda's point of view so we'll just store the stuff in a variable for now.
    saved_data = []

    if listings.first.nil?
      assert(listings.first, "No listing returned for : #{params['uc']} ")
    else
      3.times do |i|
        saved_data << {
          'type' => 'listing',
          'int_xxid' => listings[i]['Int_Xxid'],
          'timestamp' => (Time.now.to_f*1000).to_i
        }
      end
    end

    listing_with_coupons = listings.find { |listing| listing['Coupons'] && !listing['Coupons'].empty? }
    listing_with_coupons['Coupons'].each do |coupon|
      saved_data << {
          'type' => 'coupon',
          'int_xxid' => listing_with_coupons['Int_Xxid'],
          'coupon_id' => coupon['CouponId'],
          'timestamp' => (Time.now.to_f*1000).to_i
      }
    end

    # Step 2
    params = { 'vrid' => @user.vrid }

    put_with_json '/mb/upload_coupons_or_businesses', params, saved_data
    assert_response(@response, :success)

    # Step 3
    params = { 'vrid' => @user.vrid }

    get '/mb/businesses', params
    assert_response(@response, :success)
    assert_equal(3, @parsed_response['Businesses'].size, @response.body)

    get '/mb/coupons', params
    assert_response(@response, :success)
    assert_equal(listing_with_coupons['Coupons'].count, @parsed_response['Coupons'].size, @response.body)

    # Step 4
    @user = setup_user({'email' => @user.email})

    # Step 5
    params = { 'oauth_token' => @user.oauth_token }

    get '/mb/businesses', params
    assert_response(@response, :success)
    assert_equal(3, @parsed_response['Businesses'].size, @response.body)

    get '/mb/coupons', params
    assert_response(@response, :success)
    assert_equal(listing_with_coupons['Coupons'].count, @parsed_response['Coupons'].size, @response.body)

    # Step 6
    params = { 'vrid' => @user.vrid }

    get '/mb/businesses', params
    assert_response(@response, :success)
    assert_equal(0, @parsed_response['Businesses'].size, @response.body)

    get '/mb/coupons', params
    assert_response(@response, :success)
    assert_equal(0, @parsed_response['Coupons'].size, @response.body)
  end

  ##
  # Steps:
  # 1. User signs up and logs in
  # 2. User creates a custom collection
  # 3. Custom collection should show up in list of collections
  # 4. User adds a business to the custom collection
  # 5. Business should show up in the collection
  # 6. Business should show up as InMB on srp/mip
  # 7. User edits the custom collection's name.
  # 8. Custom collection should show up with new name in list of collections
  # 9. User deletes the custom collection
  # 10. Custom collection should not show up in list of collections
  # 11. Added business should no longer be InMB
  def test_custom_collections
    # Step 1
    @user = setup_user

    # Step 2
    params = {
        'oauth_token' => @user.oauth_token,
        'name' => 'Awesome Stuff'
    }

    post '/mb/collections', params
    assert_response(@response, :success)

    collection_code = @parsed_response['Collection']['Code']

    # Step 3
    params.delete('name')

    get '/mb/collections', params
    assert_response(@response, :success)
    assert_includes(@parsed_response['Collections'].map { |c| c['Name'] }, 'Awesome Stuff')

    # Step 4
    opts = { 'user_id' => @user.id }

    get_consumer_search_resp('pizza', 'glendale', opts)
    assert_response(@response, :success)

    int_xxid = @parsed_response['SearchResult']['BusinessListings'].first['Int_Xxid']

    params = {
        'oauth_token' => @user.oauth_token,
        'int_xxid' => int_xxid,
        'c' => collection_code
    }

    post '/mb/businesses', params
    assert_response(@response, :success)

    # Step 5
    params = { 'oauth_token' => @user.oauth_token }

    get "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)
    assert_equal(int_xxid, @parsed_response['Businesses'].first['Int_Xxid'])

    # Step 6
    get_consumer_search_resp('pizza', 'glendale', opts)
    assert_response(@response, :success)
    assert(@parsed_response['SearchResult']['BusinessListings'].first['Personalization']['InMB'])

    params['app_id'] = 'WEB'
    params['int_xxid'] = int_xxid

    get '/cons/business', params
    assert_response(@response, :success)
    assert(@parsed_response['Business']['Personalization']['InMB'])

    # Step 7
    params = {
        'oauth_token' => @user.oauth_token,
        'name' => 'Not Awesome',
        'description' => "random description : #{Common.random_uuid}"
    }

    put "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)

    collection_code = @parsed_response['Collection']['Code']

    # Step 8
    params.delete('name')

    get '/mb/collections', params
    assert_response(@response, :success)
    assert_includes(@parsed_response['Collections'].map { |c| c['Name'] }, 'Not Awesome')
    refute_includes(@parsed_response['Collections'].map { |c| c['Name'] }, 'Awesome Stuff')

    # Step 9
    delete "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)

    # Step 10
    get '/mb/collections', params
    assert_response(@response, :success)
    refute_includes(@parsed_response['Collections'].map { |c| c['Name'] }, 'Not Awesome')
    refute_includes(@parsed_response['Collections'].map { |c| c['Name'] }, 'Awesome Stuff')

    # Step 11
    get_consumer_search_resp('pizza', 'glendale', opts)
    assert_response(@response, :success)
    refute(@parsed_response['SearchResult']['BusinessListings'].first['Personalization']['InMB'])

    params['app_id'] = 'WEB'
    params['int_xxid'] = int_xxid

    get '/cons/business', params
    assert_response(@response, :success)
    refute(@parsed_response['Business']['Personalization']['InMB'])
  end

  ##
  # AS-5326 | Test Social Collections
  #
  # Steps:
  # 1. Owner creates custom collection, and adds businesses
  # 2. Verify UniqueCollectionId (decoded), OwnerUserId, and Count are correct
  # 3. Verify initial collection Scope of PRIVATE
  # 4. Verify User attempt to follow PRIVATE returns error
  # 5. Verify Owner update of Collection Scope to PUBLIC
  # 6. User follows Owner's PUBLIC collection
  # 7. Verify Followers key was updated
  # 8. Verify Viewer role
  # 9. Owner makes PUBLIC collection PRIVATE
  # 10. Verify User no longer able to access collection
  # 11. Owner makes PRIVATE collection PUBLIC
  # 12. Verify PUBLIC collection is not in Users collection
  # 13. User re-follows Owner's PUBLIC collection
  # 14. User copies Owner's PUBLIC collection
  # 15. Verify Owner's Collection was copied to User's mb
  # 16. User un-follows Owner's PUBLIC collection
  # 17. Verify Followers key was updated
  # 18. Verify Viewer role
  def test_social_collections
    # Step 1
    @owner = setup_user

    params = {
      'oauth_token' => @owner.oauth_token,
      'name' => 'Top Sushi Spots'
    }

    post '/mb/collections', params
    assert_response(@response, :success)

    collection_code = @parsed_response['Collection']['Code']

    opts = { 'user_id' => @owner.id }

    get_consumer_search_resp('sushi', 'burbank, ca', opts)
    assert_response(@response, :success)

    resp = @parsed_response['SearchResult']['BusinessListings'].first(3)
    int_xxids = resp.map {|listing| listing['Int_Xxid']}

    int_xxids.each do |int_xxid|
      params = {
          'oauth_token' => @owner.oauth_token,
          'int_xxid' => int_xxid,
          'c' => collection_code
      }

      post '/mb/businesses', params
      assert_response(@response, :success)
    end

    # Step 2
    params = { 'oauth_token' => @owner.oauth_token }

    get "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)

    col = @parsed_response['Collection']
    assert_equal(col['OwnerUserId'], @owner.id.to_s)
    assert_equal(col['Count'], int_xxids.length)

    ucid = decode_keys_mb(col['UniqueCollectionId'])
    assert_equal(col['OwnerCollectionId'], ucid['owner_collection_id'])
    assert_equal(col['OwnerUserId'], ucid['owner_id'])

    # Step 3
    assert_equal(col['Scope'], 'PRIVATE')

    # Step 4
    @user = setup_user

    user_params = { 'oauth_token' => @user.oauth_token }

    put "/mb/social/collections/#{col['UniqueCollectionId']}/follow", user_params
    assert_response(@response, :client_error)

    # Step 5
    params['visibility'] = 'public'

    put "/mb/social/collections/#{collection_code}/scope", params
    assert_response(@response, :success)

    params.delete('visibility')

    get "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)

    col = @parsed_response['Collection']
    assert_equal(col['Scope'], 'PUBLIC')

    # Step 6
    put "/mb/social/collections/#{col['UniqueCollectionId']}/follow", user_params
    assert_response(@response, :success)

    # Step 7
    get "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)

    col = @parsed_response['Collection']
    assert_equal(col['Followers'].first, @user.id.to_s)

    # Step 8
    get "/mb/social/public/collections/#{col['UniqueCollectionId']}", user_params
    assert_response(@response, :success)

    user_col = @parsed_response['Collection']
    assert_equal(user_col['Viewer']['Role'], 'F')

    # Step 9
    params['visibility'] = 'private'

    put "/mb/social/collections/#{collection_code}/scope", params
    assert_response(@response, :success)

    params.delete('visibility')

    get "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)

    col = @parsed_response['Collection']
    assert_nil(col['Followers'].first)

    col = @parsed_response['Collection']
    assert_equal(col['Scope'], 'PRIVATE')

    # Step 10
    get "/mb/collections/#{collection_code}", user_params
    assert_response(@response, :client_error)

    # Step 11
    params['visibility'] = 'public'

    put "/mb/social/collections/#{collection_code}/scope", params
    assert_response(@response, :success)

    params.delete('visibility')

    get "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)

    col = @parsed_response['Collection']
    assert_nil(col['Followers'].first)
    assert_equal(col['Scope'], 'PUBLIC')

    # Step 12
    get "/mb/collections/#{collection_code}", user_params
    assert_response(@response, :client_error)

    # Step 13
    put "/mb/social/collections/#{col['UniqueCollectionId']}/follow", user_params
    assert_response(@response, :success)

    # Step 14
    post "/mb/social/collections/#{col['UniqueCollectionId']}/copy", user_params
    assert_response(@response, :success)

    resp = @parsed_response['Collection']
    assert_equal(resp['Count'], 3)
    assert_equal(resp['Viewer']['Role'], 'O')

    get "/mb/collections/#{resp['Code']}", user_params
    assert_response(@response, :success)

    user_col = @parsed_response['Collection']
    assert_equal(user_col['OwnerUserId'], @user.id.to_s)
    assert_equal(user_col['Count'], 3)
    assert_equal(user_col['Viewer']['Role'], 'O')

    # Step 15
    get '/mb/collections', user_params
    assert_response(@response, :success)
    assert(@parsed_response['Collections'].detect { |x| x['Code'] == resp['Code'] })

    # Step 16
    put "/mb/social/collections/#{col['UniqueCollectionId']}/unfollow", user_params
    assert_response(@response, :success)

    # Step 17
    get "/mb/collections/#{collection_code}", params
    assert_response(@response, :success)

    col = @parsed_response['Collection']
    assert_nil(col['Followers'].first)

    # Step 18
    get "/mb/social/public/collections/#{col['UniqueCollectionId']}", user_params
    assert_response(@response, :success)

    user_col = @parsed_response['Collection']
    assert_equal(user_col['Viewer']['Role'], 'N')
  end

  ##
  # AS-5652 | Test Copied Collections
  #
  # Steps:
  # 1. Owner Signs up and creates a PUBLIC collection
  # 2. User Sign up and copies Owner's PUBLIC collection
  # 3. Verify the collection was copied to User's mb
  # 4. Owner updates original Collection: Adds Business
  # 5. Verify User's collection not updated
  # 6. Owner updates original Collection: Removes Business
  # 7. Verify User's collection not updated
  # 8. Owner updates original Collection: PUBLIC > PRIVATE
  # 9. Verify User's collection not updated
  # 10. Owner deletes original Collection
  # 11. Verify User's collection not updated
  def test_copied_collections
    # Step 1
    @owner = setup_user

    params = {
        'oauth_token' => @owner.oauth_token,
        'name' => 'Bike Shops'
    }

    post '/mb/collections', params
    assert_response(@response, :success)

    orig_collection = @parsed_response['Collection']

    opts = { 'user_id' => @owner.id }

    get_consumer_search_resp('bike shops', 'Burbank, CA', opts)
    assert_response(@response, :success)

    resp = @parsed_response['SearchResult']['BusinessListings'].first(4)
    int_xxids = resp.map {|listing| listing['Int_Xxid']}

    int_xxids.first(3).each do |int_xxid|
      params = {
          'oauth_token' => @owner.oauth_token,
          'int_xxid' => int_xxid,
          'c' => orig_collection['Code']
      }

      post '/mb/businesses', params
      assert_response(@response, :success)
    end

    params = {
        'visibility' => 'public',
        'oauth_token' => @owner.oauth_token
    }

    put "/mb/social/collections/#{orig_collection['Code']}/scope", params
    assert_response(@response, :success)

    params.delete('visibility')

    get "/mb/collections/#{orig_collection['Code']}", params
    assert_response(@response, :success)

    orig_collection = @parsed_response['Collection']

    # Step 2
    @user = setup_user

    user_params = {
        'name' => 'Bike Shops Copy',
        'oauth_token' => @user.oauth_token
    }

    post "/mb/social/collections/#{orig_collection['UniqueCollectionId']}/copy", user_params
    assert_response(@response, :success)

    copy_collection_code = @parsed_response['Collection']['Code']

    # Step 3
    user_params.delete('name')

    get '/mb/collections', user_params
    assert_response(@response, :success)

    collections = @parsed_response['Collections']
    collection_codes = collections.map {|collection| collection['Code']}
    assert_includes(collection_codes, copy_collection_code)

    # Step 4
    params = {
        'oauth_token' => @owner.oauth_token,
        'int_xxid' => int_xxids.last,
        'c' => orig_collection['Code']
    }

    post '/mb/businesses', params
    assert_response(@response, :success)

    # Step 5
    get "/mb/collections/#{copy_collection_code}", user_params
    assert_response(@response, :success)

    copied_listings = @parsed_response['Businesses']
    copied_int_xxids = copied_listings.map {|listing| listing['Int_Xxid']}
    assert_equal(int_xxids.first(3).sort, copied_int_xxids.sort)

    # Step 6
    params = {
        'oauth_token' => @owner.oauth_token,
        'int_xxid' => int_xxids.first,
        'c' => [orig_collection['Code']]
    }

    delete '/mb/businesses', params
    assert_response(@response, :success)

    # Step 7
    get "/mb/collections/#{copy_collection_code}", user_params
    assert_response(@response, :success)

    copied_listings = @parsed_response['Businesses']
    copied_int_xxids = copied_listings.map {|listing| listing['Int_Xxid']}
    assert_equal(int_xxids.first(3).sort, copied_int_xxids.sort)

    # Step 8
    params = {
        'visibility' => 'private',
        'oauth_token' => @owner.oauth_token
    }

    put "/mb/social/collections/#{orig_collection['Code']}/scope", params
    assert_response(@response, :success)

    # Step 9
    get "/mb/collections/#{copy_collection_code}", user_params
    assert_response(@response, :success)

    copied_listings = @parsed_response['Businesses']
    copied_int_xxids = copied_listings.map {|listing| listing['Int_Xxid']}
    assert_equal(int_xxids.first(3).sort, copied_int_xxids.sort)

    # Step 10
    params.delete('visibility')

    delete "/mb/collections/#{orig_collection['Code']}", params
    assert_response(@response, :success)

    # Step 11
    get "/mb/collections/#{copy_collection_code}", user_params
    assert_response(@response, :success)

    copied_listings = @parsed_response['Businesses']
    copied_int_xxids = copied_listings.map {|listing| listing['Int_Xxid']}
    assert_equal(int_xxids.first(3).sort, copied_int_xxids.sort)
  end

  ##
  # AS-5327 | Test Featured Collections
  #
  # Steps:
  # 1. User Sign up and Logs in
  # 2. Lists all featured collection
  # 3. List all collections with new filter f[] params
  # 4. List all collection with facets enabled
  # 5. User  copies featured collection
  def test_featured_collections
    # Step 1
    @user = setup_user

    # Step 2
    params = {
        'user_id' => @user.id,
        'page_id' => '123'
    }

    get '/mb/featured_collections', params
    assert_response(@response, :success)

    sub_type = @parsed_response['Collections'].map { |subtype| subtype['Subtype'] }
    assert(true, sub_type.all? { |x| x == 'FEATURED' })

    # Step 3
    params['f'] = 'geo:New York, NY'

    get '/mb/featured_collections', params
    assert_response(@response, :success)
    assert_equal('New York, NY', @parsed_response['Collections'].first['Location'])

    params['f'] = 'natl:true'

    get '/mb/featured_collections', params
    assert_response(@response, :success)
    assert(true, @parsed_response['Collections'].first['Natl'])

    # Step 4
    params.delete('f')
    params['facets'] = 'citystate'

    get '/mb/featured_collections', params
    assert_response(@response, :success)
    assert('citystate', @parsed_response['Facets'].first['FacetName'])

    params['facets'] = 'natl'

    get '/mb/featured_collections', params
    assert_response(@response, :success)
    assert('natl', @parsed_response['Facets'].first['FacetName'])

    params['facets'] = 'state'

    get '/mb/featured_collections', params
    assert_response(@response, :success)
    assert('state', @parsed_response['Facets'].first['FacetName'])

    # Step 5
    @user2 = setup_user

    params.delete('facets')

    get '/mb/featured_collections', params
    assert_response(@response, :success)

    resp = @parsed_response['Collections']
    collectionID = resp.first['UniqueCollectionId']

    params = {
        'user_id' => @user2.id,
        'name' => 'A copy of collection'
    }

    post "/mb/social/collections/#{collectionID}/copy", params
    assert_response(@response, :success)

    resp = @parsed_response['Collection']
    assert_equal(resp['Viewer']['Role'], 'O')
    assert_equal('PRIVATE', resp['Scope'])
  end

  ##
  # AS-5377 | Test Primary Collection Defaults
  #
  # Steps:
  # 1. User Sign up and Logs in
  # 2. User adds business with a primary collection
  # 3. User adds business with primary collection of 'other'
  # 4. User adds with collection specified for business with a primary collection
  # 5. User adds with collection specified for business with primary collection of 'other'
  # Cleanup
  def test_primary_collection_defaults
    # Step 1
    @user = setup_user

    # Step 2
    int_xxid = 123

    get_consumer_business_resp(int_xxid)
    assert_response(@response, :success)

    business = @parsed_response.first[1]
    assert_equal('home', business['PrimaryCollection'])

    params = { 'oauth_token' => @user.oauth_token }

    get '/mb/collections', params
    assert_response(@response, :success)

    collections = @parsed_response['Collections']
    ['home', 'food', 'services'].each do |code|
      count = collections.detect { |x| x['Code'] == code }['Count']
      assert_equal(0, count)
    end
    assert(collections.none? { |x| x['Code'] == 'other' })

    params = {
        'oauth_token' => @user.oauth_token,
        'int_xxid' => int_xxid
    }

    post '/mb/businesses', params
    assert_response(@response, :success)

    params = { 'oauth_token' => @user.oauth_token }

    get '/mb/collections', params
    assert_response(@response, :success)

    collections = @parsed_response['Collections']
    count = collections.detect { |x| x['Code'] == 'home' }['Count']
    assert_equal(1, count)

    # Step 3
    int_xxid = 22165164

    get_consumer_business_resp(int_xxid)
    assert_response(@response, :success)

    business = @parsed_response.first[1]
    assert_equal('other', business['PrimaryCollection'])

    params = {
        'oauth_token' => @user.oauth_token,
        'int_xxid' => int_xxid
    }

    post '/mb/businesses', params
    assert_response(@response, :success)

    params = { 'oauth_token' => @user.oauth_token }

    get '/mb/collections', params
    assert_response(@response, :success)

    collections = @parsed_response['Collections']
    count = collections.detect { |x| x['Code'] == 'other' }['Count']
    assert_equal(1, count)

    # Step 4
    int_xxid = 123

    get_consumer_business_resp(int_xxid)
    assert_response(@response, :success)

    business = @parsed_response.first[1]
    assert_equal('home', business['PrimaryCollection'])

    params = {
        'oauth_token' => @user.oauth_token,
        'int_xxid' => int_xxid,
        'c' => 'food'
    }

    post '/mb/businesses', params
    assert_response(@response, :success)

    params = { 'oauth_token' => @user.oauth_token }

    get '/mb/collections', params
    assert_response(@response, :success)

    collections = @parsed_response['Collections']
    count = collections.detect { |x| x['Code'] == 'food' }['Count']
    assert_equal(1, count)

    # Step 5
    int_xxid = 22165164

    get_consumer_business_resp(int_xxid)
    assert_response(@response, :success)

    business = @parsed_response.first[1]
    assert_equal('other', business['PrimaryCollection'])

    params = {
        'oauth_token' => @user.oauth_token,
        'int_xxid' => int_xxid,
        'c' => 'services'
    }

    post '/mb/businesses', params
    assert_response(@response, :success)

    params = { 'oauth_token' => @user.oauth_token }

    get '/mb/collections', params
    assert_response(@response, :success)

    collections = @parsed_response['Collections']
    count = collections.detect { |x| x['Code'] == 'services' }['Count']
    assert_equal(1, count)
  end

  ##
  # AS-4992 | Test Personalization Hash
  #
  # Steps:
  # 1. User signs up and logs in
  # 2. User adds business, coupons, and notes to mb
  # 3. Verify Personalization hash response contains correct fields and value types
  def test_personalization_hash
    # Step 1
    @user = setup_user

    # Step 2
    listings = []
    codes = []
    coupon_listings = get_listings_with_coupons_from_search

    coupon_listings.each do |listing|
      if listing['Coupons']
        params = {
            'user_id' => @user.id,
            'coupons' => listing['Coupons'][0]['CouponId'],
            'int_xxid' => listing['Int_Xxid']
        }

        post '/mb/coupons', params
        assert_response(@response, :success)
      end
    end

    # post listings & notes for that listing to mb
    listings.each do |listing|
      params = {
          'user_id' => @user.id,
          'int_xxid' => listing['Int_Xxid']
      }

      post '/mb/businesses', params
      assert_response(@response, :success)

      params = {
          'user_id' => @user.id,
          'note' => "API -- THIS IS A TEST NOTE -- #{Time.now}",
          'int_xxid' => listing['Int_Xxid']
      }

      post '/mb/notes', params
      assert_response(@response, :success)
    end

    # Step 3
    params = {
        'user_id' => @user.id,
        'include' => 'notes'
    }

    get '/mb/businesses', params
    assert_response(@response, :success)

    listings = @parsed_response['Businesses']

    personalization = ['TotalNotes', 'Notes', 'CollectionCodes', 'Ts', 'Collections',
                       'InMB', 'InCollections', 'HasNote', 'InFeaturedCollections']
    notes = ['Noteid', 'Ts', 'Uvrid', 'Int_Xxid', 'Notetype', 'Notes', 'OriginalIntXxid']
    collections = ['Code','Name','Icon','IconId']

    listings.each do |listing|
      assert(listing['Personalization'],
             "Personalization missing for Business - Listing Name: #{listing['ListingName']}, Int_Xxid: #{listing['Int_Xxid']} ")
      assert_has_keys(listing['Personalization'], personalization)
      assert_has_keys(listing['Personalization']['Notes'], notes)
      assert_has_keys(listing['Personalization']['Collections'], collections)
    end

    codes.each do |code|
      params = {
          'user_id' => @user.id,
          'include' => 'notes'
      }

      get "/mb/collections/#{code}", params
      assert_response(@response, :success)

      listings = @parsed_response['Businesses']

      listings.each do |listing|
        assert(listing['Personalization'],
               "Personalization missing for Business - Listing Name: #{listing['ListingName']}, Int_Xxid: #{listing['Int_Xxid']} ")
        assert_has_keys(listing['Personalization'], personalization)
        assert_has_keys(listing['Personalization']['Notes'], notes)
        assert_has_keys(listing['Personalization']['Collections'], collections)
      end
    end

    params = {
        'user_id' => @user.id,
        'include' => 'notes'
    }

    get '/mb/coupons', params
    assert_response(@response, :success)
    coupons = @parsed_response['Coupons']

    personalization = ['CollectionCodes', 'Collections', 'FeaturedCollections', 'ListingSummaryCounts', 'InMB']

    coupons.each do |coupon|
      assert(coupon['Business']['Personalization'],
             "Personalization missing for coupon - Listing Name: #{coupon['ListingName']}, Int_Xxid: #{coupon['Int_Xxid']} ")
      assert_has_keys(coupon['Business']['Personalization'], personalization)
    end
  end
end
