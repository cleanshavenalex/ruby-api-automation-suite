require './init'

class TestTurtleClients < APITest
  def setup
    assign_http(Config["turtle"]["host"])
    @sso_user = SSOUser.new()
    @latest_headers = nil
    @sso_verified = false
  end

  ##
  # Test GET clients, client by id, and client_info
  # ~ uses sso, and to streamline this testing it's been condensed into a single test
  #
  # Steps:
  # Setup
  # 1. Verify response for Clients (all)
  # 2. Verify response for Clients by ID
  # 3. Verify response for Client Info by Client ID
  def test_clients_client_client_info
    # Setup
    sso_response = @sso_user.login
    assert_response(sso_response, :success)

    # Step 1
    get_turtle_clients
    client = @parsed_response.sample
    assert(client.is_a?(Hash))

    assert(client['id'], client)
    assert(client['name'], client)
    assert(client['api_key'], client)
    assert(client['secret_key'], client)
    assert(client['owner'], client)
    assert(client['description'], client) if client['description']
    assert(client['created_at'], client)
    assert(client['updated_at'], client)
    assert(client['redirect_uri'], client) if client['redirect_uri']
    assert(client['requires_permissions'], client) if client['requires_permissions']
    assert(client['grant_types'], client) if client['grant_types']
    assert(client['scopes'], client) if client['scopes']
    assert(client['omniture'], client) if client['omniture']
    assert(client['appid'], client) if client['appid']
    assert(client['ptid'], client) if client['ptid']

    # Step 2
    get_turtle_client_by_id(client['id'])
    assert_match(client['name'], @response.body, client)
    assert_match(client['api_key'], @response.body, client)
    assert_match(client['secret_key'], @response.body, client)
    assert_match(client['owner'], @response.body, client)
    assert_match(client['description'], @response.body, client) if client['description']
    assert_match(client['redirect_uri'], @response.body, client) if client['redirect_uri']
    assert_match(client['requires_permissions'].to_s, @response.body, client) if client['requires_permissions']

    if client['grant_types']
      grant_types = client['grant_types'].split(',')
      grant_types.each do |gt|
        assert_match(gt, @response.body, client)
      end
    end

    if client['scopes']
      scopes = client['scopes'].split(',')
      scopes.each do |s|
        assert_match(s, @response.body, client)
      end
    end

    assert_match(client['omniture'], @response.body, client) if client['omniture']
    assert_match(client['appid'], @response.body, client) if client['appid']
    assert_match(client['ptid'], @response.body, client) if client['ptid']

    # Step 3
    get_turtle_client_info_by_client_id(client['api_key'])
    assert_equal(client['api_key'], @parsed_response['client_id'])
    assert_equal(client['name'], @parsed_response['name'])
  end

  #------------------------------------------#
  #              Helper Methods              #
  #------------------------------------------#

  def get_turtle_client_info_by_client_id(client_id=nil)
    return unless client_id
    @internal_tools = setup_user({ 'internal_tools' => true })

    headers = {
        'Authorization' => "Bearer #{@internal_tools.oauth_token}",
        'Accept' => 'application/json'
    }

    params = {
        'client_id' => client_id
    }

    get '/client_info', params, headers
    assert_response(@response, :success)

    @parsed_response
  end

  def get_turtle_client_by_id(id=nil)
    return unless @sso_verified && id

    get "/clients/#{id}", {}, @latest_headers
    assert_response(@response, :success)

    @response.body
  end

  def get_turtle_clients
    headers = {
        'Accept' => 'application/json'
    }

    get_with_sso_credentials '/clients', headers

    @sso_verified = true

    # Other Team Dragon automation sometimes adds invalid inserts that cause API to fail,
    # filtering them out of the response.
    valid_clients = []

    @parsed_response.each do |client|
      if client['name'] && client['owner'] && client['api_key']
        valid_clients << client
      end
    end

    @parsed_response = valid_clients
  end
end
