require './init'

class TestPandaUsersAddress < APITest

  USER_ADDRESS_KEYS = ['id','updated_at','created_at','user_id','description','note','street_address',
                       'city','state','zip_code','phone_number','cell_phone_number','email','is_deleted']

  def setup
    assign_http(Config['panda']['host'])
    @user = setup_user
  end

  ##
  # AS-6247 | API tests for Account User Address
  #
  # Steps:
  # 1. Verify response for adding user address via user_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses"
  # 3. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses/:id"
  def test_posting_user_address_by_user_id
    params = {
        'user_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.id}/user_address", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)

    # Step 3
    get "/usr/#{@user.id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)
  end

  ##
  # AS-6247 | API tests for Account User Address
  #
  # Steps:
  # 1. Verify response for adding user address via cookie_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses"
  # 3. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses/:id"
  def test_posting_user_address_by_cookie_id
    params = {
        'user_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.cookie_id}/user_address", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.cookie_id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)

    # Step 3
    get "/usr/#{@user.cookie_id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)
  end

  ##
  # AS-6247 | API tests for Account User Address
  #
  # Steps:
  # 1. Verify response for adding user address via user_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses"
  # 3. Verify response for updating the user addresses via user_id: PUT "/usr/:id/personal_addresses/:id"
  # 4. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses/:id"
  def test_updating_user_address_by_user_id
    params = {
        'user_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.id}/user_address", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)

    # Step 3
    params['user_address']['description'] = 'My Lair'
    params['user_address']['note'] = 'My not so humble abode'
    params['user_address']['street_address'] = '777 Lex Luther Drive'
    params['user_address']['zip_code'] = '66607'

    put "/usr/#{@user.id}/user_address", params
    assert_response(@response, :success)

    # Step 4
    get "/usr/#{@user.id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)
  end

  ##
  # AS-6247 | API tests for Account User Address
  #
  # Steps:
  # 1. Verify response for adding user address via cookie_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses"
  # 3. Verify response for updating the user addresses via cookie_id: PUT "/usr/:id/personal_addresses/:id"
  # 4. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses/:id"
  def test_updating_user_address_by_cookie_id
    params = {
        'user_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.cookie_id}/user_address", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.cookie_id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)

    # Step 3
    params['user_address']['description'] = 'My Lair'
    params['user_address']['note'] = 'My not so humble abode'
    params['user_address']['street_address'] = '777 Lex Luther Drive'
    params['user_address']['zip_code'] = '66607'

    put "/usr/#{@user.cookie_id}/user_address", params
    assert_response(@response, :success)

    # Step 4
    get "/usr/#{@user.cookie_id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)
  end

  ##
  # AS-6247 | API tests for Account User Address
  #
  # Steps:
  # 1. Verify response for adding user address via user_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses"
  # 3. Compare Panda versus dragon response for the user addresses via user_id
  # 4. Verify response for deleting the user addresses via user_id: DELETE "/usr/:id/personal_addresses/:id"
  def test_deleting_user_address_by_user_id
    params = {
        'user_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.id}/user_address", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)

    # Step 3
    delete "/usr/#{@user.id}/user_address", {}
    assert_response(@response, :success)

    get "/usr/#{@user.id}/user_address", {}
    assert_response(@response, :client_error)
  end

  ##
  # AS-6247 | API tests for Account User Address
  #
  # Steps:
  # 1. Verify response for adding user address via cookie_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses"
  # 3. Compare Panda versus dragon response for the user addresses via user_id
  # 4. Verify response for deleting the user addresses via cookie_id: DELETE "/usr/:id/personal_addresses/:id"
  def test_deleting_user_address_by_cookie_id
    params = {
        'user_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.cookie_id}/user_address", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.cookie_id}/user_address", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['user_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['user_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['user_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['user_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['user_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)

    # Step 3
    delete "/usr/#{@user.cookie_id}/user_address", {}
    assert_response(@response, :success)

    get "/usr/#{@user.cookie_id}/user_address", {}
    assert_response(@response, :client_error)
  end

  ##
  # AS-6990 | API tests for Account Personal Addresses
  #
  # Steps:
  # 1. Verify response for adding user address via user_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses"
  # 3. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses/:id"
  def test_posting_personal_addresses_by_user_id
    params = {
        'personal_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.id}/personal_addresses", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.id}/personal_addresses", {}
    assert_response(@response, :success)
    personal_address = @parsed_response.first

    assert_has_keys(personal_address, USER_ADDRESS_KEYS)
    refute_nil(personal_address['id'], personal_address)

    assert_equal(@user.id, personal_address['user_id'], personal_address)
    assert_equal(params['personal_address']['description'], personal_address['description'], personal_address)
    assert_equal(params['personal_address']['street_address'], personal_address['street_address'], personal_address)
    assert_equal(params['personal_address']['city'], personal_address['city'], personal_address)
    assert_equal(params['personal_address']['state'], personal_address['state'], personal_address)
    assert_equal(params['personal_address']['zip_code'], personal_address['zip_code'], personal_address)

    # Step 3
    get "/usr/#{@user.id}/personal_addresses/#{personal_address['id']}", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['personal_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['personal_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['personal_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['personal_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['personal_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)
  end

  ##
  # AS-6990 | API tests for Account Personal Addresses
  #
  # Steps:
  # 1. Verify response for adding user address via cookie_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses"
  # 3. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses/:id"
  def test_posting_personal_addresses_by_cookie_id
    params = {
        'personal_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.cookie_id}/personal_addresses", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.cookie_id}/personal_addresses", {}
    assert_response(@response, :success)
    personal_address = @parsed_response.first

    assert_has_keys(personal_address, USER_ADDRESS_KEYS)
    refute_nil(personal_address['id'], personal_address)

    assert_equal(@user.id, personal_address['user_id'], personal_address)
    assert_equal(params['personal_address']['description'], personal_address['description'], personal_address)
    assert_equal(params['personal_address']['street_address'], personal_address['street_address'], personal_address)
    assert_equal(params['personal_address']['city'], personal_address['city'], personal_address)
    assert_equal(params['personal_address']['state'], personal_address['state'], personal_address)
    assert_equal(params['personal_address']['zip_code'], personal_address['zip_code'], personal_address)

    # Step 3
    get "/usr/#{@user.cookie_id}/personal_addresses/#{personal_address['id']}", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['personal_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['personal_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['personal_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['personal_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['personal_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)
  end

  ##
  # AS-6990 | API tests for Account Personal Addresses
  #
  # Steps:
  # 1. Verify response for adding user address via user_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses"
  # 3. Verify response for updating the user addresses via user_id: PUT "/usr/:id/personal_addresses/:id"
  # 4. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses/:id"
  def test_updating_personal_addresses_by_user_id
    params = {
        'personal_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.id}/personal_addresses", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.id}/personal_addresses", {}
    assert_response(@response, :success)
    personal_address = @parsed_response.first

    assert_has_keys(personal_address, USER_ADDRESS_KEYS)
    refute_nil(personal_address['id'], personal_address)

    assert_equal(@user.id, personal_address['user_id'], personal_address)
    assert_equal(params['personal_address']['description'], personal_address['description'], personal_address)
    assert_equal(params['personal_address']['street_address'], personal_address['street_address'], personal_address)
    assert_equal(params['personal_address']['city'], personal_address['city'], personal_address)
    assert_equal(params['personal_address']['state'], personal_address['state'], personal_address)
    assert_equal(params['personal_address']['zip_code'], personal_address['zip_code'], personal_address)

    # Step 3
    params['personal_address']['description'] = 'My Lair'
    params['personal_address']['note'] = 'My not so humble abode'
    params['personal_address']['street_address'] = '777 Lex Luther Drive'
    params['personal_address']['zip_code'] = '66607'

    put "/usr/#{@user.id}/personal_addresses/#{personal_address['id']}", params
    assert_response(@response, :success)

    # Step 4
    get "/usr/#{@user.id}/personal_addresses/#{personal_address['id']}", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['personal_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['personal_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['personal_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['personal_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['personal_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)
  end

  ##
  # AS-6990 | API tests for Account Personal Addresses
  #
  # Steps:
  # 1. Verify response for adding user address via cookie_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses"
  # 3. Verify response for updating the user addresses via cookie_id: PUT "/usr/:id/personal_addresses/:id"
  # 4. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses/:id"
  def test_updating_personal_addresses_by_cookie_id
    params = {
        'personal_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.cookie_id}/personal_addresses", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.cookie_id}/personal_addresses", {}
    assert_response(@response, :success)
    personal_address = @parsed_response.first

    assert_has_keys(personal_address, USER_ADDRESS_KEYS)
    refute_nil(personal_address['id'], personal_address)

    assert_equal(@user.id, personal_address['user_id'], personal_address)
    assert_equal(params['personal_address']['description'], personal_address['description'], personal_address)
    assert_equal(params['personal_address']['street_address'], personal_address['street_address'], personal_address)
    assert_equal(params['personal_address']['city'], personal_address['city'], personal_address)
    assert_equal(params['personal_address']['state'], personal_address['state'], personal_address)
    assert_equal(params['personal_address']['zip_code'], personal_address['zip_code'], personal_address)

    # Step 3
    params['personal_address']['description'] = 'My Lair'
    params['personal_address']['note'] = 'My not so humble abode'
    params['personal_address']['street_address'] = '777 Lex Luther Drive'
    params['personal_address']['zip_code'] = '66607'

    put "/usr/#{@user.cookie_id}/personal_addresses/#{personal_address['id']}", params
    assert_response(@response, :success)

    # Step 4
    get "/usr/#{@user.cookie_id}/personal_addresses/#{personal_address['id']}", {}
    assert_response(@response, :success)

    assert_has_keys(@parsed_response, USER_ADDRESS_KEYS)
    refute_nil(@parsed_response['id'], @parsed_response)

    assert_equal(@user.id, @parsed_response['user_id'], @parsed_response)
    assert_equal(params['personal_address']['description'], @parsed_response['description'], @parsed_response)
    assert_equal(params['personal_address']['street_address'], @parsed_response['street_address'], @parsed_response)
    assert_equal(params['personal_address']['city'], @parsed_response['city'], @parsed_response)
    assert_equal(params['personal_address']['state'], @parsed_response['state'], @parsed_response)
    assert_equal(params['personal_address']['zip_code'], @parsed_response['zip_code'], @parsed_response)
  end

  ##
  # AS-6990 | API tests for Account Personal Addresses
  #
  # Steps:
  # 1. Verify response for adding user address via user_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via user_id: GET "/usr/:id/personal_addresses"
  # 3. Compare Panda versus dragon response for the user addresses via user_id
  # 4. Verify response for deleting the user addresses via user_id: DELETE "/usr/:id/personal_addresses/:id"
  def test_deleting_personal_addresses_by_user_id
    params = {
        'personal_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.id}/personal_addresses", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.id}/personal_addresses", {}
    assert_response(@response, :success)
    personal_address = @parsed_response.first

    assert_has_keys(personal_address, USER_ADDRESS_KEYS)
    refute_nil(personal_address['id'], personal_address)

    assert_equal(@user.id, personal_address['user_id'], personal_address)
    assert_equal(params['personal_address']['description'], personal_address['description'], personal_address)
    assert_equal(params['personal_address']['street_address'], personal_address['street_address'], personal_address)
    assert_equal(params['personal_address']['city'], personal_address['city'], personal_address)
    assert_equal(params['personal_address']['state'], personal_address['state'], personal_address)
    assert_equal(params['personal_address']['zip_code'], personal_address['zip_code'], personal_address)

    # Step 3
    delete "/usr/#{@user.id}/personal_addresses/#{personal_address['id']}", {}
    assert_response(@response, :success)

    get "/usr/#{@user.id}/personal_addresses/#{personal_address['id']}", {}
    assert_response(@response, :client_error)
  end

  ##
  # AS-6990 | API tests for Account Personal Addresses
  #
  # Steps:
  # 1. Verify response for adding user address via cookie_id: POST "/usr/:id/personal_addresses"
  # 2. Verify response for retrieving the user addresses via cookie_id: GET "/usr/:id/personal_addresses"
  # 3. Compare Panda versus dragon response for the user addresses via user_id
  # 4. Verify response for deleting the user addresses via cookie_id: DELETE "/usr/:id/personal_addresses/:id"
  def test_deleting_personal_addresses_by_cookie_id
    params = {
        'personal_address' => {
            'description' => 'My Personal Address',
            'note' => 'One Address to Rule All Others',
            'street_address' => '1831 Lois Lane',
            'city' => 'Smallville',
            'state' => 'KS',
            'zip_code' => '66606',
            'phone_number' => '7855551212',
            'cell_phone_number' => '7855557676',
            'email' => 'superman@smallville.email.com'
        }
    }

    # Step 1
    post "/usr/#{@user.cookie_id}/personal_addresses", params
    assert_response(@response, :success)

    # Step 2
    get "/usr/#{@user.cookie_id}/personal_addresses", {}
    assert_response(@response, :success)
    personal_address = @parsed_response.first

    assert_has_keys(personal_address, USER_ADDRESS_KEYS)
    refute_nil(personal_address['id'], personal_address)

    assert_equal(@user.id, personal_address['user_id'], personal_address)
    assert_equal(params['personal_address']['description'], personal_address['description'], personal_address)
    assert_equal(params['personal_address']['street_address'], personal_address['street_address'], personal_address)
    assert_equal(params['personal_address']['city'], personal_address['city'], personal_address)
    assert_equal(params['personal_address']['state'], personal_address['state'], personal_address)
    assert_equal(params['personal_address']['zip_code'], personal_address['zip_code'], personal_address)

    # Step 3
    delete "/usr/#{@user.cookie_id}/personal_addresses/#{personal_address['id']}", {}
    assert_response(@response, :success)

    get "/usr/#{@user.cookie_id}/personal_addresses/#{personal_address['id']}", {}
    assert_response(@response, :client_error)
  end
end
