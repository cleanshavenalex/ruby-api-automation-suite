require './init'

class TestSnakeProfiles < APITest
  def setup
    @user = TurtleUser.new
    @api_key = Config["snake"]["api_key"]
    assign_http(Config["snake"]["host"])
  end

  ##
  # AS-5734 | Test different profiles
  #
  # Steps:
  # 1. Get the response for yp45 & yp46
  # 2. Validate keys fom yp45 & yp46
  def test_difference_in_profiles_keys
    #Step 1
    params = { 'prof' => 'yp45' }

    get_snake_consumer_business_resp(params)
    assert_response(@response, :success)
    yp45results = @parsed_response['business']

    params = { 'prof' => 'yp46' }

    get_snake_consumer_business_resp(params)
    assert_response(@response, :success)
    yp46results = @parsed_response['business']

    results = yp46results.keys.sort - yp45results.keys.sort
    assert_empty(results)
  end

  ##
  # AS-5734 | Test different profiles
  #
  # Steps:
  # Setup
  # 1. Verify response for Snake yp45 profile
  # 2. Verify response for Snake yp46 profile
  # 3. Validate the additional fandango key in yp45/yp46 Keys
  def test_difference_in_additional_keys
    # Setup
    int_xxid = '481321326'

    assign_http(Config["rhino"]["host"])

    rhino_path = "/thanos/int_xxid?q=#{int_xxid}&sources=listing%2ClistingAttrs%2Ccoupon%2CappearanceAttrs%2Chugo"

    get rhino_path, {}
    assert_response(@response, :success)
    features = @parsed_response['results'].first['Features']
    assert_backend_has_keys(features, ['Fandango','Actions'])

    # Step 1
    assign_http(Config["snake"]["host"])

    @extra_keys = %w[fandango]

    params = {
        'int_xxid' => int_xxid,
        'prof' => 'yp45'
    }

    # Step 2
    get_snake_consumer_business_resp(params)
    assert_response(@response, :success)
    yp45results = @parsed_response['business']
    @yp45 = []
    yp45results.values.each do |h|
      if h.is_a?(Hash)
        @yp45.push(*h.keys)
      end
    end

    params['prof'] = 'yp46'

    get_snake_consumer_business_resp(params)
    assert_response(@response, :success)
    yp46results = @parsed_response['business']
    @yp46 = []
    yp46results.values.each do |h|
      if h.is_a?(Hash)
        @yp46.push(*h.keys)
      end
    end

    # Step 3
    @actual_keys = @yp46 - @yp45
    assert_equal(@extra_keys, @actual_keys)
  end
end
