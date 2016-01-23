module FacebookHelpers
  CONSUMER = {
      client_id: '126257704231029',
      client_secret: '999875b94cced914eed3551a18af105c',
      access_token: '126257704231029|XWt9VvUiNJ2zD9eJnvSZsJLqVgo'
  }

  def get_app_oauth_token
    params = {
        'client_id' => CONSUMER[:client_id],
        'client_secret' => CONSUMER[:client_secret],
        'grant_type' => 'client_credentials'
    }

    post '/oauth/access_token', params

    @response
  end

  def create_fb_user(with_permissions = true)
    preserve_original_http(Config["facebook"]["host"]) do
      params = {
          'access_token' => CONSUMER[:access_token],
          'installed' => with_permissions ? 'true' : 'false',
          'name' => 'user',
          'locale' => 'en_US',
          'permissions' => 'read_stream,email',
          'method' => 'post'
      }

      post "/#{CONSUMER[:client_id]}/accounts/test-users", params
      assert_response(@response, :success)

      @parsed_response
    end
  end

  def login_fb_user!(fb_user, turtle_user)
    preserve_original_http(Config["turtle"]["host"]) do
      headers = { 'Accept' => 'application/json' }

      params = {
          'grant_type' => 'password',
          'username' => '',
          'password' => '',
          'provider' => 'facebook',
          'access_token' => fb_user['access_token'],
          'vrid' => turtle_user.vrid,
          'merge_history' => true
      }

      post_with_basic_auth '/oauth/access_token', Config["turtle"]["client_id"],
                                                  Config["turtle"]["secret_key"],
                                                  params,
                                                  headers
      # debugging:
      assert_response(@response, :success)
      assert(@parsed_response['access_token'])

      turtle_user.oauth_token = @parsed_response['access_token']

      get_user_info(turtle_user.oauth_token)
      assert(@parsed_response['id'])

      turtle_user.id = @parsed_response['id']
    end
  end

  def reset_password(user_id, new_password='pa$$word')
    preserve_original_http(Config["facebook"]["host"]) do
      params = {
          'oauth_token' => CONSUMER[:access_token],
          'password' => new_password,
          'method' => 'post'
      }

      #reset password path
      post "/#{user_id}", params

      @response.body == "true"
    end
  end

  def get_all_test_users
    preserve_original_http(Config["facebook"]["host"]) do
      params = { 'oauth_token' => CONSUMER[:access_token] }

      get "/#{CONSUMER[:client_id]}/accounts/test-users", params

      @parsed_response['data']
    end
  end

  def delete_all_test_users
    users = get_all_test_users

    users.each do |u|
      delete_test_user u
    end
  end

  def get_user(u)
    preserve_original_http(Config["facebook"]["host"]) do
      params = { 'oauth_token' => CONSUMER[:access_token] }

      get "/#{u['id']}", params

      @parsed_response
    end
  end

  def delete_test_user(u)
    preserve_original_http(Config["facebook"]["host"]) do
      params = {
          'method' => 'delete',
          'oauth_token' => CONSUMER[:access_token]
      }

      delete "/#{u['id']}", params

      @response.body # true
    end
  end
end
