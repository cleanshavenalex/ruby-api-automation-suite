require './init'

class TestTurtleDeepLinkTokens < APITest
  def setup
    assign_http(Config["turtle"]["host"])

    @sso_user = SSOUser.new
    @latest_headers = nil
  end

  # AS-6402, AS-6446, AS-6503
  #
  # Step 1: Create 3 users.
  # Step 2: Access the form to create tokens.
  # Step 3: Verify that the user returned for each token is the correct user
  # Step 4: Delete the tokens for each user
  # Step 5: Verify that the tokens no longer work
  def test_deep_link_tokens
    # Step 1
    user1 = setup_user
    user2 = setup_user
    user3 = setup_user

    # Step 2
    sso_response = @sso_user.login
    assert_response(sso_response, :success)

    get_with_sso_credentials('/deep_link_tokens')
    assert_response(@response, :success)

    file = generate_csv_file([
      [user1.email, ''],
      [user2.email, 'email'],
      [user3.email, 'test']
    ])

    post_multipart_file('/deep_link_tokens', {}, file, @latest_headers)
    assert_response(@response, :success)

    tokens = parse_tokens(@response.body)

    # Step 3
    get "/deep_link_tokens/#{tokens[user1.email]}", {}
    assert_response(@response, :success)
    assert_equal(user1.email, @parsed_response['user']['email'], @parsed_response)
    assert_equal(nil, @parsed_response['scope'], @parsed_response)

    get "/deep_link_tokens/#{tokens[user2.email]}", {}
    assert_response(@response, :success)
    assert_equal(user2.email, @parsed_response['user']['email'], @parsed_response)
    assert_equal('email', @parsed_response['scope'], @parsed_response)

    get "/deep_link_tokens/#{tokens[user3.email]}", {}
    assert_response(@response, :success)
    assert_equal(user3.email, @parsed_response['user']['email'], @parsed_response)
    assert_equal('test', @parsed_response['scope'], @parsed_response)

    # Step 4
    delete "/deep_link_tokens/#{tokens[user1.email]}", {}
    assert_response(@response, :success)

    delete "/deep_link_tokens/#{tokens[user2.email]}", {}
    assert_response(@response, :success)

    delete "/deep_link_tokens/#{tokens[user3.email]}", {}
    assert_response(@response, :success)

    # Step 5
    get "/deep_link_tokens/#{tokens[user1.email]}", {}
    assert_response(@response, :client_error)

    get "/deep_link_tokens/#{tokens[user2.email]}", {}
    assert_response(@response, :client_error)

    get "/deep_link_tokens/#{tokens[user3.email]}", {}
    assert_response(@response, :client_error)
  end

  private

  # Format for the data is a 2D array:
  # [
  #    [email, scope],
  #    [email, scope],
  #    ...
  # ]
  def generate_csv_file(data=[])
    data.map! do |entry|
      entry.join(",")
    end

    data.join("\n")
  end

  def parse_tokens(response)
    tokens = {}

    response.split("\n").each do |row|
      k,v = row.split(",")
      tokens[k] = v
    end

    tokens
  end
end
