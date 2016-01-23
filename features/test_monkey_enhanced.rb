require './init'

class TestMonkeyEnhanced < APITest
  def setup
    assign_http(Config['monkey']['host'])
    @api_key = Config['monkey']['api_key']
    @user = setup_user

    # Find an existing int_xxid to add images to. Delete all images on it
    # for ease of testing.
    @int_xxid = get_rateable_int_xxids_from_search('dentists', 'north, sc').sample
    delete_all_images_from_int_xxid(@int_xxid)
  end

  def teardown
    # Clean up after test finishes.
    delete_all_images_from_int_xxid(@int_xxid)
  end

  ##
  # Images are sorted as follows:
  #   1. b_image_image_relation.primary
  #   2. b_image_tag.cover
  #   3. b_image_tag.profile
  #   4. b_image_tag.logo
  #   5. b_image_image_relation.created_at desc
  def test_monkey_multi_with_enhanced_mip_sorting
    skip('Sorting by tags is not implemented at this time.')

    # Upload 6 images to test sorting.
    image1 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)
    image2 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)
    image3 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)
    image4 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)
    image5 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)
    image6 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)

    # Test default sorting
    get_images_from_int_xxids(@int_xxid)
    assert_response(@response, :success)

    relations = @parsed_response['relations']
    expected_order = [image6, image5, image4, image3, image2, image1]
    actual_order = relations.map {|rel| rel['id']}
    assert_equal(expected_order, actual_order)

    # Add tags/primary to adjust sorting.
    params = {
      'api_key' => @api_key,
      'primary' => 'true'
    }

    post "/b_image/#{image1}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    params = {
      'api_key' => @api_key,
      'tags'    => {
        'cover' => 'true'
      }
    }

    post "/b_image/#{image2}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    params = {
      'api_key' => @api_key,
      'tags'    => {
        'profile' => 'true'
      }
    }

    post "/b_image/#{image3}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    params = {
      'api_key' => @api_key,
      'tags'    => {
        'logo' => 'true'
      }
    }

    post "/b_image/#{image4}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    post "/b_image/#{image5}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    # Test sorting with tags and primary
    get_images_from_int_xxids(@int_xxid)
    assert_response(@response, :success)

    relations = @parsed_response['relations']
    expected_order = [image1, image2, image3, image5, image4, image6]
    actual_order = relations.map {|rel| rel['id']}
    assert_equal expected_order, actual_order
  end

  ##
  # AS-7464 | Support Multiple tags
  #
  # These tags can only be used once per image on a business and will
  # automatically unset the tag(s) on the current image if/when set:
  # ~ cover, profile, logo
  #
  # Multiple tags can now be set at the same time on one image:
  # ~ cover, profile, logo, stock
  #
  # Steps
  # Setup: images, tags
  # 1. All tags set on first image
  # 2. Multiple set / randomized tags applied to second image,
  #    unset tags from first except stock
  def test_monkey_multi_enhanced_mip_setting_tags
    # Setup
    image1 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)
    image2 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)
    tags1 = {
        'cover' => true,
        'profile' => true,
        'logo' => true,
        'stock' => true
    }
    tags2 = {
        'cover' => true,
        'profile' => [true, false].sample,
        'logo' => false,
        'stock' => true
    }

    # Step 1
    params = {
      'api_key' => @api_key,
      'tags' => tags1
    }

    post "/b_image/#{image1}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    get_images_from_int_xxids(@int_xxid)
    assert_response(@response, :success)
    assert_equal(2, @parsed_response['relations'].length, @parsed_response)

    image1_data = @parsed_response['relations'].find { |rel| rel['id'] == image1 }
    refute_nil(image1_data, "Expected image1 to be returned /b_image/int_xxid/#{@int_xxid}")
    image2_data = @parsed_response['relations'].find { |rel| rel['id'] == image2 }
    refute_nil(image2_data, "Expected image1 to be returned /b_image/int_xxid/#{@int_xxid}")

    tags1.each_key { |k|
      assert_includes(image1_data['tags'], k)
      refute_includes(image2_data['tags'], k)
    }

    # Step 2
    params = {
      'api_key' => @api_key,
      'tags' => tags2
    }

    post "/b_image/#{image2}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    get_images_from_int_xxids(@int_xxid)
    assert_response(@response, :success)
    assert_equal(2, @parsed_response['relations'].length, @parsed_response)

    image1_data = @parsed_response['relations'].find { |rel| rel['id'] == image1 }
    refute_nil(image1_data, "Expected image1 to be returned /b_image/int_xxid/#{@int_xxid}")
    image2_data = @parsed_response['relations'].find { |rel| rel['id'] == image2 }
    refute_nil(image2_data, "Expected image1 to be returned /b_image/int_xxid/#{@int_xxid}")

    tags2.each do |k, v|
      if v
        if k == 'stock'
          assert_includes(image2_data['tags'], k)
          assert_includes(image1_data['tags'], k)
        else
          assert_includes(image2_data['tags'], k)
          refute_includes(image1_data['tags'], k)
        end
      else
        refute_includes(image2_data['tags'], k)
        assert_includes(image1_data['tags'], k)
      end
    end
  end

  ##
  # Images will not be returned if they are outside the date range
  # defined in the start_date and end_date columns. If recurring is
  # true, then the year is ignored.
  #
  # When paginating, images that are missing due to the date range
  # should not mess up the pagination.
  def test_monkey_multi_enhanced_mip_date_ranges_and_recurring
    image1 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)
    image2 = upload_and_link_image('int_xxid', @int_xxid, @user.oauth_token)

    # Set a start_date one week before, end_date one week later, and
    # recurring false for image2.
    params = {
      'api_key'    => @api_key,
      'start_date' => (Time.now - 1.week).to_i,
      'end_date'   => (Time.now + 1.week).to_i,
      'recurring'  => 'false'
    }

    post "/b_image/#{image2}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    # Between the two remaining images, image2 should display first
    # if it is not hidden. We will limit the response to the first
    # image relation to test the pagination at the same time.
    get_images_from_int_xxids(@int_xxid, "limit" => 1)
    assert_response(@response, :success)

    relations = @parsed_response['relations']
    assert_equal 1, relations.size
    assert_equal image2, relations.first['id']

    # Now set recurring to true and ensure that image2 still appears.
    params = {
      'api_key'    => @api_key,
      'recurring'  => 'true'
    }

    post "/b_image/#{image2}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    get_images_from_int_xxids(@int_xxid, "limit" => 1)
    assert_response(@response, :success)

    relations = @parsed_response['relations']
    assert_equal 1, relations.size
    assert_equal image2, relations.first['id']

    # Set a start_date one week after, end_date one week before, and
    # recurring false for image2.
    params = {
      'api_key'    => @api_key,
      'start_date' => (Time.now + 1.week).to_i,
      'end_date'   => (Time.now - 1.week).to_i,
      'recurring'  => 'false'
    }

    post "/b_image/#{image2}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    # image2 should now be hidden so image1 should show up.
    get_images_from_int_xxids(@int_xxid, "limit" => 1)
    assert_response(@response, :success)

    relations = @parsed_response['relations']
    assert_equal 1, relations.size
    assert_equal image1, relations.first['id']

    # Now set recurring to true and ensure that image1 still appears.
    params = {
      'api_key'    => @api_key,
      'recurring'  => 'true'
    }

    post "/b_image/#{image2}/int_xxid/#{@int_xxid}", params
    assert_response(@response, :success)

    get_images_from_int_xxids(@int_xxid, "limit" => 1)
    assert_response(@response, :success)

    relations = @parsed_response['relations']
    assert_equal 1, relations.size
    assert_equal image1, relations.first['id']
  end
end
