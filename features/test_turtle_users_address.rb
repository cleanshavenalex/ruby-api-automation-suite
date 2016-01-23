require './init'

class TestTurtleUsersAddress < APITest

  def setup
    assign_http(Config["turtle"]["host"])
    @user = TurtleUser.new
  end

  ##
  # AS-6422 | Add missing address endpoints to Turtle
  # ~ PUT /usr params['address'] & GET /user_address
  #
  # Steps:
  # 1. Verify response for adding address: PUT /usr params['address']
  # 2. Verify response for getting address: GET /user_address
  # 3. Verify response for updating address: PUT /usr params['address']
  # 4. Verify response for getting updated address: GET /user_address
  def test_create_update_and_get_user_address
    # Setup
    @user = setup_user
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}"}

    # Step 1
    params = {
        'address' => {
            'street_address' => '123 Oak Ave',
            'city' => 'Awesomeville',
            'state' => 'CA',
            'zip_code' => '77577'
        }
    }

    put '/usr', params, headers
    assert_response(@response, :success)
    refute_nil(@parsed_response['user_address'], @parsed_response)
    user_address = @parsed_response['user_address']
    assert(user_address['id'], user_address)
    assert_equal(@user.id, user_address['user_id'], user_address)
    assert_equal(params['address']['street_address'], user_address['street_address'], user_address)
    assert_equal(params['address']['city'], user_address['city'], user_address)
    assert_equal(params['address']['state'], user_address['state'], user_address)
    assert_equal(params['address']['zip_code'], user_address['zip_code'], user_address)

    # Step 2
    get '/user_address', {}, headers
    assert_response(@response, :success)
    assert(@parsed_response['address'], @parsed_response)
    address = @parsed_response['address']
    assert_equal(user_address['id'], address['id'], address)
    assert_equal(user_address['user_id'], address['user_id'], address)
    assert_equal(user_address['street_address'], address['street_address'], address)
    assert_equal(user_address['city'], address['city'], address)
    assert_equal(user_address['state'], address['state'], address)
    assert_equal(user_address['zip_code'], address['zip_code'], address)

    # Step 3
    params = {
        'address' => {
            'street_address' => '657 Pine Ln',
            'city' => 'Awesomerville',
            'state' => 'CA',
            'zip_code' => '77944'
        }
    }

    put '/usr', params, headers
    assert_response(@response, :success)
    refute_nil(@parsed_response['user_address'], @parsed_response)
    user_address = @parsed_response['user_address']
    assert_equal(address['id'], user_address['id'], user_address)
    assert_equal(address['user_id'], user_address['user_id'], user_address)
    assert_equal(params['address']['street_address'], user_address['street_address'], user_address)
    assert_equal(params['address']['city'], user_address['city'], user_address)
    assert_equal(address['state'], user_address['state'], user_address)
    assert_equal(params['address']['zip_code'], user_address['zip_code'], user_address)

    # Step 4
    get '/user_address', {}, headers
    assert_response(@response, :success)
    assert(@parsed_response['address'], @parsed_response)
    address = @parsed_response['address']
    assert_equal(user_address['id'], address['id'], address)
    assert_equal(user_address['user_id'], address['user_id'], address)
    assert_equal(user_address['street_address'], address['street_address'], address)
    assert_equal(user_address['city'], address['city'], address)
    assert_equal(user_address['state'], address['state'], address)
    assert_equal(user_address['zip_code'], address['zip_code'], address)
  end

  ##
  # AS-6422 | Add missing address endpoints to Turtle
  # ~ DELETE /user_address
  #
  # Steps:
  # 1. Verify response for adding address: PUT /usr params['address']
  # 2. Verify response for getting address: GET /user_address
  # 3. Verify response for deleting address: DELETE /user_address
  # 4. Verify response for getting deleted address: GET /user_address
  def test_create_get_and_delete_user_address
    # Setup
    @user = setup_user
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}"}

    # Step 1
    params = {
        'address' => {
            'street_address' => '123 Oak Ave',
            'city' => 'Awesomeville',
            'state' => 'CA',
            'zip_code' => '77577'
        }
    }

    put '/usr', params, headers
    assert_response(@response, :success)
    refute_nil(@parsed_response['user_address'], @parsed_response)
    user_address = @parsed_response['user_address']
    assert(user_address['id'], user_address)
    assert_equal(@user.id, user_address['user_id'], user_address)
    assert_equal(params['address']['street_address'], user_address['street_address'], user_address)
    assert_equal(params['address']['city'], user_address['city'], user_address)
    assert_equal(params['address']['state'], user_address['state'], user_address)
    assert_equal(params['address']['zip_code'], user_address['zip_code'], user_address)

    # Step 2
    get '/user_address', {}, headers
    assert_response(@response, :success)
    assert(@parsed_response['address'], @parsed_response)
    address = @parsed_response['address']
    assert_equal(user_address['id'], address['id'], address)
    assert_equal(user_address['user_id'], address['user_id'], address)
    assert_equal(user_address['street_address'], address['street_address'], address)
    assert_equal(user_address['city'], address['city'], address)
    assert_equal(user_address['state'], address['state'], address)
    assert_equal(user_address['zip_code'], address['zip_code'], address)

    # Step 3
    delete '/user_address', {}, headers
    assert_response(@response, :success)

    get '/user_address', {}, headers
    assert_response(@response, :client_error)
    assert_equal('AddressNotFoundError', @parsed_response['error'], @parsed_response)
    assert_equal('AddressNotFoundError', @parsed_response['message'], @parsed_response)
  end

  ##
  # AS-6422 | Add missing address endpoints to Turtle
  # ~ POST | PUT | GET /personal_addresses, /personal_addresses/:id
  #
  # Steps:
  # 1. Verify response for adding address: POST /personal_addresses
  # 2. Verify response for getting address: GET /personal_addresses
  # 3. Verify response for updating address: PUT /personal_addresses/:id
  # 4. Verify response for getting updated address: GET /personal_addresses/:id
  def test_create_update_and_get_personal_addresses
    # Setup
    @user = setup_user
    type = 'PersonalAddress'
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}"}

    # Step 1
    params = {
        'address' => {
            'description' => 'My_Home_123',
            'street_address' => '123 Oak Ave',
            'city' => 'Awesomeville',
            'state' => 'CA',
            'zip_code' => '77577'
        }
    }

    post '/personal_addresses', params, headers
    assert_response(@response, :success)
    assert(@parsed_response['address'].first, @parsed_response)
    personal_address = @parsed_response['address']
    assert(personal_address['id'], personal_address)
    type_id = personal_address['id']
    assert_equal(@user.id, personal_address['user_id'], personal_address)
    assert_equal(params['address']['description'], personal_address['description'], personal_address)
    assert_equal(params['address']['street_address'], personal_address['street_address'], personal_address)
    assert_equal(params['address']['city'], personal_address['city'], personal_address)
    assert_equal(params['address']['state'], personal_address['state'], personal_address)
    assert_equal(params['address']['zip_code'], personal_address['zip_code'], personal_address)

    # Step 2
    get '/personal_addresses', {}, headers
    assert_response(@response, :success)
    assert(@parsed_response['addresses'].first, @parsed_response)
    address = @parsed_response['addresses'].first
    assert_equal(personal_address['id'], address['id'], address)
    assert_equal(personal_address['user_id'], address['user_id'], address)
    assert_equal(personal_address['description'], address['description'], address)
    assert_equal(personal_address['street_address'], address['street_address'], address)
    assert_equal(personal_address['city'], address['city'], address)
    assert_equal(personal_address['state'], address['state'], address)
    assert_equal(personal_address['zip_code'], address['zip_code'], address)

    # Step 3
    params = {
        'address' => {
            'description' => 'My_Home_657',
            'street_address' => '657 Pine Ln',
            'city' => 'Awesomerville',
            'state' => 'CA',
            'zip_code' => '77944'
        }
    }

    put "/personal_addresses/#{personal_address['id']}", params, headers
    assert_response(@response, :success)
    assert(@parsed_response['address'], @parsed_response)
    personal_address = @parsed_response['address']
    assert_equal(address['id'], personal_address['id'], personal_address)
    assert_equal(address['user_id'], personal_address['user_id'], personal_address)
    assert_equal(params['address']['description'], personal_address['description'], personal_address)
    assert_equal(params['address']['street_address'], personal_address['street_address'], personal_address)
    assert_equal(params['address']['city'], personal_address['city'], personal_address)
    assert_equal(address['state'], personal_address['state'], personal_address)
    assert_equal(params['address']['zip_code'], personal_address['zip_code'], personal_address)

    # Step 4
    get "/personal_addresses/#{personal_address['id']}", {}, headers
    assert_response(@response, :success)
    assert(@parsed_response['address'], @parsed_response)
    address = @parsed_response['address']
    assert_equal(personal_address['id'], address['id'], address)
    assert_equal(personal_address['user_id'], address['user_id'], address)
    assert_equal(personal_address['description'], address['description'], address)
    assert_equal(personal_address['street_address'], address['street_address'], address)
    assert_equal(personal_address['city'], address['city'], address)
    assert_equal(personal_address['state'], address['state'], address)
    assert_equal(personal_address['zip_code'], address['zip_code'], address)
  end

  ##
  # AS-6422 | Add missing address endpoints to Turtle
  # ~ POST | DELETE | GET /personal_addresses, /personal_addresses/:id
  #
  # Steps:
  # 1. Verify response for adding address: POST /personal_addresses
  # 2. Verify response for getting address: GET /personal_addresses
  # 3. Verify response for deleting address: DELETE /personal_addresses/:id
  # 4. Verify response for getting deleted address: GET /personal_addresses
  def test_create_multiple_delete_single_and_get_personal_addresses
    # Setup
    @user = setup_user
    type = 'PersonalAddress'
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}"}
    params = []
    personal_addresses = []

    params << {
        'address' => {
            'description' => 'My_Home_123',
            'street_address' => '123 Oak Ave',
            'city' => 'Awesomeville',
            'state' => 'CA',
            'zip_code' => '77577'
        }
    }

    params << {
        'address' => {
            'description' => 'My_Home_657',
            'street_address' => '657 Pine Ln',
            'city' => 'Awesomerville',
            'state' => 'CA',
            'zip_code' => '77944'
        }
    }

    # Step 1
    params.each do |params|
      post '/personal_addresses', params, headers
      assert_response(@response, :success)
      assert(@parsed_response['address'], @parsed_response)
      personal_addresses << @parsed_response['address']
      assert(@parsed_response['address']['id'], @parsed_response)
      assert_equal(@user.id, @parsed_response['address']['user_id'], @parsed_response)
      assert_equal(params['address']['description'], @parsed_response['address']['description'], @parsed_response)
      assert_equal(params['address']['street_address'], @parsed_response['address']['street_address'], @parsed_response)
      assert_equal(params['address']['city'], @parsed_response['address']['city'], @parsed_response)
      assert_equal(params['address']['state'], @parsed_response['address']['state'], @parsed_response)
      assert_equal(params['address']['zip_code'], @parsed_response['address']['zip_code'], @parsed_response)
    end

    delete_id = personal_addresses[0]['id']
    type_id = personal_addresses[1]['id']

    # Step 2
    get '/personal_addresses', {}, headers
    assert_response(@response, :success)
    assert(@parsed_response['addresses'].length == 2, @parsed_response)

    personal_addresses.each do |personal_address|
      address = @parsed_response['addresses'].find { |x| x['id'] == personal_address['id'] }
      refute_nil(address)

      assert_equal(personal_address['user_id'], address['user_id'], address)
      assert_equal(personal_address['description'], address['description'], address)
      assert_equal(personal_address['street_address'], address['street_address'], address)
      assert_equal(personal_address['city'], address['city'], address)
      assert_equal(personal_address['state'], address['state'], address)
      assert_equal(personal_address['zip_code'], address['zip_code'], address)
    end

    # Step 3
    delete "/personal_addresses/#{delete_id}", {}, headers
    assert_response(@response, :success)

    # Step 4
    get '/personal_addresses', {}, headers
    assert_response(@response, :success)
    assert(@parsed_response['addresses'].length == 1, @parsed_response)
    assert(@parsed_response['addresses'].first, @parsed_response)
    address = @parsed_response['addresses'].first
    assert_equal(type_id, address['id'], address)
    assert_equal(personal_addresses[1]['user_id'], address['user_id'], address)
    assert_equal(personal_addresses[1]['description'], address['description'], address)
    assert_equal(personal_addresses[1]['street_address'], address['street_address'], address)
    assert_equal(personal_addresses[1]['city'], address['city'], address)
    assert_equal(personal_addresses[1]['state'], address['state'], address)
    assert_equal(personal_addresses[1]['zip_code'], address['zip_code'], address)
  end
end
