require './init'

class TestMonkeyBaseFeatures < APITest
  def setup
    @api_key = Config['monkey']['api_key']
    assign_http(Config['monkey']['host'])
  end

  ##
  # Upload and view image
  #
  # Steps:
  # Setup
  # 1. Get uploaded image
  def test_monkey_upload
    # Setup
    @user = setup_user
    image = generate_random_image
    sha1 = upload_image(@user.oauth_token, image)

    # Step 1
    get "/b_image/#{sha1}", {}
    assert_response(@response, :success)
    assert_equal(image, @response.body)
  end

  ##
  # Upload and Delete image for business
  #
  # Steps:
  # 1. Register User
  # 2. Search for Pizza in Glendale
  # 3. Upload image
  # 4. Link image
  # 5. "Unlink" image by user.
  # 6. View image
  def test_monkey_upload_and_delete_from_business
    # Step 1
    @user = setup_user

    # Step 2
    int_xxid = get_rateable_int_xxids_from_search('pizza', 'austin, tx').first

    # Step 3
    sha1 = upload_image(@user.oauth_token)

    # Step 4
    link_image(sha1, 'int_xxid', int_xxid, @user.oauth_token)
    assert_response(@response, :success)

    get "/business/#{int_xxid}/images", 'api_key' => @api_key
    assert_response(@response, :success)
    assert(@parsed_response.map { |images| images['id'] }.include?(sha1), 'Image not found in list after add.')

    # Step 5
    params = {
        'reason' => 6,
        'ext_type' => 'int_xxid',
        'ext_id' => int_xxid,
        'oauth_token' => @user.oauth_token,
        'api_key' => @api_key
    }
    post "/b_image/#{sha1}/int_xxid/#{int_xxid}/report", params
    assert_response(@response, :success)

    # Step 6
    get "/business/#{int_xxid}/images", 'api_key' => @api_key
    if @response.code =~ /^2\d{2}$/
      refute(@parsed_response.map { |images| images['id'] }.include?(sha1), 'Image still found in list after delete.')
    else
      assert_response(@response, 404)
    end
  end

  ##
  # AS-5801 | User Profile/Settings - Enabled upload of user profile images
  # - PUT '/b_image/user_id/:id/upload_and_link'
  #
  # Steps:
  # 1. Register User
  # 2. Upload & Link image
  # 3. Get all images for user
  # 4. Verify the image details
  def test_monkey_upload_for_user
    # Step 1
    @user = setup_user

    # Step 2
    upload_and_link_image_by_user_id(@user)
    assert_response(@response, :success)

    # Step 3
    params = {
        'user_id' => @user.id,
        'api_key' => @api_key
    }

    get '/user', params
    assert_response(@response, :succes)

    # Step 4
    assert(@parsed_response['count'] == 1, @parsed_response)
    image = @parsed_response['images'].first
    assert(image['image_path'], image)
    assert_equal('user_id', image['type_name'], image)
    assert_equal('XX3', image['user_type'], image)
    assert_equal(@user.id.to_s, image['ext_id'], image)
    assert_equal(@user.id, image['user_id'], image)
    assert_equal(@user.display_name, image['user'], image)
    assert_match(@user.cookie_id, image['caption'], image)
  end

  ##
  # AS-5801 | User Profile/Settings - Enabled upload of user profile images
  # - PUT '/b_image/int_xxid/:id/upload_and_link'
  #
  # Steps:
  # 1. Register User
  # 2. Get Int_Xxid
  # 3. Upload & Link image
  # 4. Get all images for user
  # 5. Verify the image details
  # 6. Get all images for int_xxid
  # 7. Verify the image is linked to the int_xxid
  def test_monkey_upload_for_user_to_int_xxid
    # Step 1
    @user = setup_user

    # Step 2
    int_xxid = get_rateable_int_xxids_from_search('pizza', 'los angeles, ca').sample

    # Step 3
    upload_and_link_image_for_int_xxid_by_user(int_xxid, @user)
    assert_response(@response, :success)

    # Step 4
    params = {
        'user_id' => @user.id,
        'api_key' => @api_key
    }

    get '/user', params
    assert_response(@response, :succes)

    # Step 5
    assert(@parsed_response['count'] == 1, @parsed_response)
    image = @parsed_response['images'].first
    assert(image['image_path'], image)
    assert_equal('int_xxid', image['type_name'], image)
    assert_equal('int_xxid', image['user_type'], image)
    assert_equal(int_xxid, image['ext_id'], image)
    assert_equal(@user.id, image['user_id'], image)
    assert_equal(@user.display_name, image['user'], image)
    assert_match(@user.cookie_id, image['caption'], image)
    sha1 = image['id']

    # Step 6
    params = { 'api_key' => @api_key }

    get "/business/images/#{int_xxid}", params
    assert_response(@response, :success)

    # Step 7
    check = nil
    @parsed_response["#{int_xxid}"].each do |image|
      if image['id'] == sha1
        check = sha1
        break
      end
    end
    refute_nil(check, "Expected to the image id: #{sha1} to be added to int_xxid: #{int_xxid}")
  end

  ##
  # AS-6277 | Integrate monkey with adult filter
  # - PUT '/b_image/user_id/:id/upload_and_link'
  #
  # Speaking with Sudheer Sahu, Amit Rawat, James He, and Christian Sousa Rodriguez, it was agreed that for captions
  # (and business reviews) that we should reject for Obscene, but allow those returned as Adult by the QIS API
  # EXAMPLE: http://REDACTED
  #
  # Steps:
  # 1. Register User
  # 2. Upload & Link image with OBSCENE profanity in the caption
  # 3. Verify error response for OBSCENE profanity in caption
  # 4. Verify response for upload & Link image with ADULT profanity (acceptable) in the caption
  # 5. Verify response for upload & Link image without any profanity in the caption
  # 6. Get all images for user
  # 7. Verify the image details
  def test_monkey_upload_and_link_with_profane_caption
    # Step 1
    @user = setup_user

    # Step 2
    caption = 'My horse is the shit!'
    upload_and_link_image_by_user_id(@user, nil, caption)
    assert_response(@response, :client_error)

    # Step 3
    assert_equal('Error', @parsed_response['error'], @parsed_response)
    assert_equal('Sorry! Please keep it clean. Your caption may not contain profanity.', @parsed_response['message'], @parsed_response)

    # Step 4
    caption = 'Checkout my super sexy horse!'
    upload_and_link_image_by_user_id(@user, nil, caption)
    assert_response(@response, :success)

    # Step 5
    caption = 'Look at my horse its amazing!'

    upload_and_link_image_by_user_id(@user, nil, caption)
    assert_response(@response, :success)

    # Step 6
    params = {
        'user_id' => @user.id,
        'api_key' => @api_key
    }

    get '/user', params
    assert_response(@response, :success)

    # Step 7
    assert(@parsed_response['count'] == 1, @parsed_response)
    image = @parsed_response['images'].first
    assert(image['image_path'], image)
    assert_equal('user_id', image['type_name'], image)
    assert_equal('XX3', image['user_type'], image)
    assert_equal(@user.id.to_s, image['ext_id'], image)
    assert_equal(@user.id, image['user_id'], image)
    assert_equal(@user.display_name, image['user'], image)
    assert_match(caption, image['caption'], image)
  end

  ##
  # AS-6905 | Auth required for media to Update Caption or Delete Image
  # ~ PUT '/b_image/:sha1/:ext_type/:ext_id'
  # ~ DELETE '/b_image/:sha1'
  #
  # Steps:
  # Setup
  # 1. Upload & Link image with caption
  # 2. Verify response for update to caption without oauth_token
  # 3. Verify response for update to caption with oauth_token
  # 4. Verify response for deleting image without oauth_token
  # 5. Verify response for deleting image with oauth_token
  def test_auth_required_for_media_to_update_or_delete
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

    int_xxid = nil
    @parsed_response['SearchResult']['BusinessListings'].each do |business|
      if business['Rateable'] == 1 && business['Int_Xxid']
        int_xxid = business['Int_Xxid']
        break
      end
    end

    # Step 1
    upload_and_link_image_for_int_xxid_by_user(int_xxid, @user)
    assert_response(@response, :success)

    sha1 = @parsed_response['id']

    # Step 2
    params = {
        'caption' => "UPDATED CAPTION -- Check out this picture #{@user.cookie_id}",
        'api_key' => Config["monkey"]["api_key"],
        'metadata' => {
            'user_type' => 'YPMobile',
            'user' => @user.first_name,
            'user_id' => @user.id
        }
    }

    put "/media/#{sha1}/int_xxid/#{int_xxid}", params
    assert_response(@response, :client_error)

    # Step 3
    params['oauth_token'] = @user.oauth_token

    put "/media/#{sha1}/int_xxid/#{int_xxid}", params
    assert_response(@response, :success)

    # Step 4
    params = {
        'api_key' => Config["monkey"]["api_key"]
    }

    delete "/media/#{sha1}", params
    assert_response(@response, :client_error)

    # Step 5
    params['oauth_token'] = @user.oauth_token

    delete "/media/#{sha1}", params
    assert_response(@response, :success)
  end

  ##
  # AS-7315 | Endpoint needed to upload and display photos associated with reviews
  #
  # Steps:
  # Setup
  # 1. User adds reviews and images
  # 2. Verify response for get '/media/reviews'
  # 3. User updates reviews
  # 4. Verify response for get '/media/reviews' still linked to int_xxid / review
  # 5. Verify response for delete '/media/:sha1/listings/:int_xxid'
  # 6. Verify response for delete '/media/reviews/:id'
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
        break if int_xxids.length == 3
      end
    end

    # Step 1
    rating_ids = []
    int_xxids.each do |int_xxid|
      review_business(int_xxid, @user.oauth_token)
      assert_response(@response, :success)
      rating_ids << @parsed_response['RatingID']
    end

    count = 0
    images = []
    caption = 'Check out this picture!'

    int_xxids.each do |int_xxid|
      opts = {
          'rating_id' => rating_ids[count]
      }

      upload_and_link_image_for_int_xxid_by_user(int_xxid, @user, generate_random_image, caption, opts)
      assert_response(@response, :success)
      images << @parsed_response

      if count > 1
        upload_and_link_image_for_int_xxid_by_user(int_xxid, @user, generate_random_image, caption, opts)
        assert_response(@response, :success)
        images << @parsed_response
      end

      count += 1
    end

    # Step 2
    params = {
        'api_key' => @api_key,
        'ids' => rating_ids
    }

    get '/media/reviews', params
    assert_response(@response, :success)
    refute_empty(@parsed_response, 'Endpoint: /media/reviews')

    media_reviews = []
    rating_ids.each do |rating_id|
      assert_equal(@parsed_response[rating_id]['images'].length, @parsed_response[rating_id]['count'])

      @parsed_response[rating_id]['images'].each do |image|
        assert(images.find { |i| i['id'] == image['id'] }, 'Expected image id to match initial upload')
        assert_equal(@user.id, image['user_id'])
        assert_equal('int_xxid', image['user_type'])
        assert_equal('int_xxid', image['type_name'])
        assert_equal('public', image['state_name'])
        assert_equal('image', image['b_image_media_type'])
        assert_equal(caption, image['caption'])
        assert(int_xxids.include?(image['ext_id']),
               "Expected image ext_id #{image['ext_id']} to match int_xxid from initial upload: #{int_xxids}")

        media_reviews << image
      end
    end

    # Step 3
    assign_http(Config['panda']['host'])

    rating_ids.each do |rating_id|
      params = {
          'id' => rating_id,
          'rating' => {
              'body' => 'It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness...',
              'value' => 5
          }
      }

      put "/rats/#{rating_id}", params
      assert_response(@response, :success)
    end

    # Step 4
    assign_http(Config['monkey']['host'])

    params = {
        'api_key' => @api_key,
        'ids' => rating_ids
    }

    get '/media/reviews', params
    assert_response(@response, :success)
    refute_empty(@parsed_response, 'Endpoint: /media/reviews')

    rating_ids.each do |rating_id|
      assert_equal(@parsed_response[rating_id]['images'].length, @parsed_response[rating_id]['count'])

      @parsed_response[rating_id]['images'].each do |image|
        assert(media_reviews.find { |i| i['id'] == image['id'] }, 'Expected image id to match initial upload')
        assert_equal(@user.id, image['user_id'])
        assert_equal('int_xxid', image['user_type'])
        assert_equal('int_xxid', image['type_name'])
        assert_equal('public', image['state_name'])
        assert_equal('image', image['b_image_media_type'])
        assert_equal(caption, image['caption'])
        assert(int_xxids.include?(image['ext_id']),
               "Expected image ext_id #{image['ext_id']} to match int_xxid from initial upload: #{int_xxids}")
      end
    end

    # Step 5
    params = {
        'api_key' => @api_key,
        'oauth_token' => @user.oauth_token,
        'rating_id' => rating_ids[0]
    }

    delete "/media/#{images[0]['id']}/listings/#{int_xxids[0]}", params
    assert_response(@response, :success)

    # Step 6
    params = {
        'api_key' => @api_key,
        'oauth_token' => @user.oauth_token,
    }

    delete "/media/reviews/#{rating_ids[1]}", params
    assert_response(@response, :success)
  end
end
