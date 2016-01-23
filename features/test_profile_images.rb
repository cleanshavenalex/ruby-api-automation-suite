require './init'

class TestProfileImages < APITest
  def setup
    @monkey_api_key = Config['monkey']['api_key']
  end

  ##
  # Steps:
  # 1. Create a new user.
  # 2. Upload a profile image to monkey for user.
  # 3. Check that the profile image is correct on Turtle /me.
  # 4. Check that the profile image is correct on Panda /usr/profile.
  # 5. Remove profile image from monkey.
  # 6. Check that the profile image is gone on Turtle /me.
  # 7. Check that the profile image is gone on Panda /usr/profile.
  # 8. Upload the same image as profile image to monkey.
  # 9. Check that the image is correct on Turtle /me.
  # 10. Check that the image is correct on Panda /usr/profile.
  # 11. Remove profile image from monkey.
  # 12. Upload a new image as profile image to monkey.
  # 13. Check that the image is correct on Turtle /me.
  # 14. Check that the image is correct on Panda /usr/profile.
  def test_upload_delete_profile_image_for_basic_user
    # Step 1
    @user = setup_user

    # Step 2
    assign_http(Config['monkey']['host'])
    sha1 = upload_image(@user.oauth_token)

    params = {
      'oauth_token' => @user.oauth_token,
      'api_key' => @monkey_api_key
    }
    put "/media/#{sha1}/profile", params
    assert_response(@response, :success)

    # Step 3
    assign_http(Config['turtle']['host'])
    headers = {
      'Authorization' => "Bearer #{@user.oauth_token}"
    }
    get '/me', {}, headers
    assert_response(@response, :success)
    assert_match(sha1, @parsed_response['avatar_url'])

    # Step 4
    assign_http(Config['panda']['host'])
    params = {
      'user_id' => @user.id
    }
    get '/usr/profile', params
    assert_response(@response, :success)
    assert_match(sha1, @parsed_response['User']['AvatarURL'])

    # Step 5
    assign_http(Config['monkey']['host'])
    params = {
      'oauth_token' => @user.oauth_token,
      'api_key' => @monkey_api_key
    }
    delete "/media/#{sha1}/profile", params
    assert_response(@response, :success)

    # Step 6
    assign_http(Config['turtle']['host'])
    headers = {
      'Authorization' => "Bearer #{@user.oauth_token}"
    }
    get '/me', {}, headers
    assert_response(@response, :success)
    assert_nil(@parsed_response['avatar_url'])

    # Step 7
    assign_http(Config['panda']['host'])
    params = {
      'user_id' => @user.id
    }
    get '/usr/profile', params
    assert_response(@response, :success)
    assert_nil(@parsed_response['User']['AvatarURL'])

    # Step 8
    assign_http(Config['monkey']['host'])
    params = {
      'oauth_token' => @user.oauth_token,
      'api_key' => @monkey_api_key
    }
    put "/media/#{sha1}/profile", params
    assert_response(@response, :success)

    # Step 9
    assign_http(Config['turtle']['host'])
    headers = {
      'Authorization' => "Bearer #{@user.oauth_token}"
    }
    get '/me', {}, headers
    assert_response(@response, :success)
    assert_match(sha1, @parsed_response['avatar_url'])

    # Step 10
    assign_http(Config['panda']['host'])
    params = {
      'user_id' => @user.id
    }
    get '/usr/profile', params
    assert_response(@response, :success)
    assert_match(sha1, @parsed_response['User']['AvatarURL'])

    # Step 11
    assign_http(Config['monkey']['host'])
    params = {
      'oauth_token' => @user.oauth_token,
      'api_key' => @monkey_api_key
    }
    delete "/media/#{sha1}/profile", params
    assert_response(@response, :success)

    # Step 12
    assign_http(Config['monkey']['host'])
    new_sha1 = upload_image(@user.oauth_token)

    params = {
      'oauth_token' => @user.oauth_token,
      'api_key' => @monkey_api_key
    }
    put "/media/#{new_sha1}/profile", params
    assert_response(@response, :success)

    # Step 13
    assign_http(Config['turtle']['host'])
    headers = {
      'Authorization' => "Bearer #{@user.oauth_token}"
    }
    get '/me', {}, headers
    assert_response(@response, :success)
    assert_match(new_sha1, @parsed_response['avatar_url'])

    # Step 14
    assign_http(Config['panda']['host'])
    params = {
      'user_id' => @user.id
    }
    get '/usr/profile', params
    assert_response(@response, :success)
    assert_match(new_sha1, @parsed_response['User']['AvatarURL'])
  end
end
