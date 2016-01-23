module DragonHelpers
  def get_dragon_user(user_id)
    preserve_original_http(Config["dragon"]["host"]) do

      get "/dragon/unified_users/#{user_id}", {}

      if @response.code =~ /^2\d{2}$/
        @parsed_response = @parsed_response.deep_underscore_keys
        @parsed_response = @parsed_response['unified_user']
      end

      @response
    end
  end

  def get_dragon_user_address(user_id)
    preserve_original_http(Config["dragon"]["host"]) do

      get "/dragon/unified_users/#{user_id}/user_address", {}

      if @response.code =~ /^2\d{2}$/
        @parsed_response = @parsed_response.deep_underscore_keys
        @parsed_response = @parsed_response['address']
      end

      @response
    end
  end

  def get_dragon_user_personal_addresses(user_id, address_id=nil)
    preserve_original_http(Config["dragon"]["host"]) do

      if address_id
        get "/dragon/unified_users/#{user_id}/personal_addresses/#{address_id}", {}
      else
        get "/dragon/unified_users/#{user_id}/personal_addresses", {}
      end

      if @response.code =~ /^2\d{2}$/
        @parsed_response = @parsed_response.deep_underscore_keys
      end

      @response
    end
  end

  def get_dragon_email_subscriptions(user_id)
    preserve_original_http(Config["dragon"]["host"]) do

      get "/dragon/em_subscriptions/#{user_id}", {}

      if @response.code =~ /^2\d{2}$/
        @parsed_response = @parsed_response.deep_underscore_keys
        @parsed_response = @parsed_response['email_subscription']
      end

      @response
    end
  end

  def get_dragon_user_by_access_token(access_token)
    preserve_original_http(Config["dragon"]["host"]) do

      get "/dragon/access_tokens/?access_token=#{access_token}", {}

      if @response.code =~ /^2\d{2}$/
        @parsed_response = @parsed_response.deep_underscore_keys
        @parsed_response = @parsed_response['access_token']
      end

      @response
    end
  end

  def get_dragon_user_accounts(user_id, all_accounts=false)
    preserve_original_http(Config["dragon"]["host"]) do

      get "/dragon/unified_user_accounts/#{user_id}", {}

      if @response.code =~ /^2\d{2}$/
        @parsed_response = @parsed_response.deep_underscore_keys
        @parsed_response = @parsed_response['accounts']
        @parsed_response = @parsed_response.first unless all_accounts
      end

      @response
    end
  end

  def get_dragon_nonregistered_user(user_email)
    preserve_original_http(Config["dragon"]["host"]) do

      get "/dragon/nonregistered_users/#{user_email}", {}

      if @response.code =~ /^2\d{2}$/
        @parsed_response = @parsed_response.deep_underscore_keys
        @parsed_response = @parsed_response['nonregistered_user']
      end

      @response
    end
  end

  def get_dragon_turtle_clients(client_id=nil)
    preserve_original_http(Config["dragon"]["host"]) do

      if client_id
        get "/dragon/clients/#{client_id}", {}

        if @response.code =~ /^2\d{2}$/
          @parsed_response = @parsed_response.deep_underscore_keys
          @parsed_response = @parsed_response['turtle_clients']
        end
      else
        get "/dragon/clients", {}

        if @response.code =~ /^2\d{2}$/
          @parsed_response = @parsed_response.deep_underscore_keys
          @parsed_response = @parsed_response['turtle_client']
        end
      end

      @response
    end
  end
end
