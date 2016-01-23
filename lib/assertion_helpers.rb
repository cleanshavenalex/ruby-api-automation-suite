module AssertionHelpers
  # accepts the response, a specific code or specified type, and an optional message
  def assert_response(response, type, msg=nil)
    if msg
      message = "#{msg}, #{response.code} #{response.body}"
    else
      message = "#{response.code} #{response.body}"
    end

    if type.kind_of?(Integer)
      assert_equal(type, response.code.to_i, message)
    else
      case type
        when :success
          assert_match(/^2\d{2}$/, response.code.to_s, message)
        when :redirect
          assert_match(/^3\d{2}$/, response.code.to_s, message)
        when :client_error
          assert_match(/^4\d{2}$/, response.code.to_s, message)
      end
    end
  end

  # confirms the response within inspectify
  # works similar to assert_response, but requires @parsed_response
  def assert_inspectify_response(parsed_response, type, msg=nil)
    if msg
      message = "#{msg}, #{parsed_response['status']} #{parsed_response}"
    else
      message = "#{parsed_response['status']} #{parsed_response}"
    end

    if type.kind_of?(Integer)
      assert_equal(type, parsed_response['status'].to_i, message)
    else
      case type
        when :success
          assert_match(/^2\d{2}$/, parsed_response['status'].to_s, message)
        when :redirect
          assert_match(/^3\d{2}$/, parsed_response['status'].to_s, message)
        when :client_error
          assert_match(/^4\d{2}$/, parsed_response['status'].to_s, message)
      end
    end
  end

  def refute_image_in_consumer_business(sha1, listing)
    int_xxid = listing['Int_Xxid']

    assign_http(Config["panda"]["host"])

    ## check consumer/business
    params = { 'int_xxid' => int_xxid }

    get '/cons/business', params
    assert_response(@response, :success)

    total_count = @parsed_response['Business']['Media']['TotalCount']

    get '/cons/business/media', params.merge(h: total_count)
    assert_response(@response, :success)

    b_image_shas = @parsed_response['Media']['Data'].map do |images|
      images['Id']
    end

    refute(b_image_shas.include?(sha1), 'Image visible in ImgPaths.')
  end

  def refute_rating_in_listing(rating_id, listing)
    lid = listing['ListingId']

    assign_http(Config["panda"]["host"])

    ## check ratings
    params = { 'lid' => lid }

    get '/rats/get_ratings_for_business', params
    assert_response(@response, :success)

    ratings = @parsed_response['Ratings'].map do |rating|
      rating['id']
    end

    refute(ratings.include?(rating_id), 'Review found in ratings for business')
  end

  def assert_image_in_consumer_business(sha1, listing)
    int_xxid = listing['Int_Xxid']

    assign_http(Config["panda"]["host"])

    ## check consumer/business
    params = {
      'int_xxid' => int_xxid,
      'h' => '5',
      'o' => '0'
    }

    get '/cons/business/media', params
    assert_response(@response, :success)

    b_image_shas = @parsed_response['Media']['Data'].map do |images|
      images['Id']
    end

    assert(b_image_shas.include?(sha1), "Image #{sha1} not visible in ImgPaths in /cons/business/media.")
  end

  def assert_rating_in_listing(rating_id, listing)
    lid = listing['ListingId']

    assign_http(Config["panda"]["host"])

    ## check ratings
    params = { 'lid' => lid }

    get '/rats/get_ratings_for_business', params
    assert_response(@response, :success)

    ratings = @parsed_response['Ratings'].map do |rating|
      rating['id']
    end

    assert ratings.include?(rating_id), 'Review not visible in /rats/get_ratings_for_business.'
  end

  def assert_image_in_profile(sha1, user)
    assign_http(Config["panda"]["host"])

    ## check profile
    path = '/usr/images'
    params = {
        'user_id' => user.id,
        'oauth_token' => user.oauth_token
    }

    get path, params
    assert_response(@response, :success)
    assert_equal(sha1, @parsed_response['images'].first['id'])
  end

  def assert_rating_in_profile(rating_id, user)
    assign_http(Config["panda"]["host"])

    params = {
        'user_id' => user.id,
        'oauth_token' => user.oauth_token
    }

    get '/usr/reviews', params
    assert_response(@response, :success)
    assert_equal(rating_id, @parsed_response.first['id'])
  end

  def assert_has_keys(hash, expected_keys)
    hash_keys = hash.keys rescue hash.first.keys

    missing_keys = expected_keys - hash_keys

    assert(missing_keys.empty?, "Expected keys not found in hash: #{missing_keys.join(", ")}")
  end

  def refute_has_keys(hash, unexpected_keys)
    hash_keys = hash.keys

    intersecting_keys = unexpected_keys & hash_keys

    assert(intersecting_keys.empty?, "Unexpected keys found in hash: #{intersecting_keys.join(", ")}")
  end

  def assert_backend_has_keys(hash, expected_keys)
    hash_keys = hash.keys rescue hash.first.keys

    missing_keys = expected_keys - hash_keys

    skip("Expected backend keys not found in hash: #{missing_keys.join(", ")}") unless missing_keys.empty?
  end

  def assert_dragon_user_params(expected_hash, obj_hash, check_private=false)
    # expected_hash should be the panda response

    basic_params = ['id','first_name','last_name','email','email_token','cookie_id','is_deleted','marketing_output','sex',
                    'hide_third_party_photo','site','suppressed','terms','verified','zip_code','communication_options']
    private_params = ['password_hash','password_salt']
    check = []

    basic_params.each do |param|
      if expected_hash.has_key?(param.to_sym) && obj_hash.has_key?(param.to_sym)
        if expected_hash[param] != obj_hash[param]
          check << "Expected: #{param} => #{expected_hash[param]}, to match: #{obj_hash[param]}"
        end
      end
    end

    private_params.each do |param|
      if expected_hash.has_key?(param.to_sym) && obj_hash.has_key?(param.to_sym)
        if expected_hash[param] != obj_hash[param]
          check << "Expected: #{param} => #{expected_hash[param]}, to match: #{obj_hash[param]}"
        end
      end
    end if check_private

    assert_empty(check)
  end

  def assert_dragon_user_address_params(expected_hash, obj_hash)
    # expected_hash should be the panda response

    basic_params = ['street_address','city','state','zip_code']
    check = []

    basic_params.each do |param|
      if expected_hash.has_key?(param.to_sym) && obj_hash.has_key?(param.to_sym)
        if expected_hash[param] != obj_hash[param]
          check << "Expected: #{param} => #{expected_hash[param]}, to match: #{obj_hash[param]}"
        end
      end
    end

    assert_empty(check)
  end

  def assert_dragon_user_account_params(expected_hash, obj_hash)
    # expected_hash should be the panda response

    basic_params = ['user_id','type','identifier','access_token','avatar_url']
    check = []

    basic_params.each do |param|
      if expected_hash.has_key?(param.to_sym) && obj_hash.has_key?(param.to_sym)
        if expected_hash[param] != obj_hash[param]
          check << "Expected: #{param} => #{expected_hash[param]}, to match: #{obj_hash[param]}"
        end
      end
    end

    assert_empty(check)
  end

  def assert_dragon_user_email_subscriptions_params(expected_hash, obj_hash)
    # expected_hash should be the panda response

    basic_params = ['user_id','feedback','recommendations','recommendations_auto','recommendations_entertainment',
                    'recommendations_family','recommendations_health','recommendations_home','recommendations_restaurants',
                    'recommendations_shopping','recommendations_sports','recommendations_travel','updates']
    check = []

    basic_params.each do |param|
      if expected_hash.has_key?(param.to_sym) && obj_hash.has_key?(param.to_sym)
        if expected_hash[param] != obj_hash[param]
          check << "Expected: #{param} => #{expected_hash[param]}, to match: #{obj_hash[param]}"
        end
      end
    end

    assert_empty(check)
  end
end
