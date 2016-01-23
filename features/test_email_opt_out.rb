require './init'

class TestEmailOptOut < APITest
  def setup
    assign_http(Config['panda']['host'])
  end

  ##
  # Steps:
  # 1. User signs up with email opted in.
  # 2. Send share listing email should succeed.
  # 3. User updates to email opted out.
  # 4. Send share listing email should fail.
  def test_register_with_opt_in_update_with_opt_out
    # Step 1
    @user = setup_user('email_opt_in' => 'true')

    # Step 2
    listings = []
    response = get_consumer_search_resp('pizza', 'los angeles, ca')
    response['SearchResult']['BusinessListings'].each do |listing|
      listings << listing['Int_Xxid']
    end

    params = {
        'request_host' => 'http://www.xx.com',
        'to' => @user.email,
        'from' => @user.email,
        'from_name' => @user.first_name,
        'lid' => listings.sample.to_s,
        'note' => 'Checkout this listing!',
        'mobile' => false
    }

    post '/em/share_listing', params
    assert_response(@response, :success)

    # Step 3
    assign_http(Config['turtle']['host'])
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    params = {
      'email_opt_in' => 'false'
    }

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 4
    assign_http(Config['panda']['host'])
    params = {
        'request_host' => 'http://www.xx.com',
        'to' => @user.email,
        'from' => @user.email,
        'from_name' => @user.first_name,
        'lid' => listings.sample.to_s,
        'note' => 'Checkout this listing!',
        'mobile' => false
    }

    post '/em/share_listing', params
    assert_response(@response, :client_error)
  end

  ##
  # Steps:
  # 1. User signs up with email opted out.
  # 2. Send share listing email should fail.
  # 3. User updates to email opted in.
  # 4. Send share listing email should succeed.
  def test_register_with_opt_out_update_with_opt_in
    # Step 1
    @user = setup_user('email_opt_in' => 'false')

    # Step 2
    listings = []
    response = get_consumer_search_resp('pizza', 'los angeles, ca')
    response['SearchResult']['BusinessListings'].each do |listing|
      listings << listing['Int_Xxid']
    end

    params = {
        'request_host' => 'http://www.xx.com',
        'to' => @user.email,
        'from' => @user.email,
        'from_name' => @user.first_name,
        'lid' => listings.sample.to_s,
        'note' => 'Checkout this listing!',
        'mobile' => false
    }

    post '/em/share_listing', params
    assert_response(@response, :client_error)

    # Step 3
    assign_http(Config['turtle']['host'])
    headers = { 'Authorization' => "Bearer #{@user.oauth_token}" }

    params = {
      'email_opt_in' => 'true'
    }

    put '/usr', params, headers
    assert_response(@response, :success)

    # Step 4
    assign_http(Config['panda']['host'])
    params = {
        'request_host' => 'http://www.xx.com',
        'to' => @user.email,
        'from' => @user.email,
        'from_name' => @user.first_name,
        'lid' => listings.sample.to_s,
        'note' => 'Checkout this listing!',
        'mobile' => false
    }

    post '/em/share_listing', params
    assert_response(@response, :success)
  end
end
