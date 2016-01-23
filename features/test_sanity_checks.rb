require './init'

class TestSanityChecks < APITest
  # Recorded issues that don't fall into a specific bucket, but still needed during regression checks

  def setup
    assign_http(Config["panda"]["host"])
    @vrid = "api-test-#{SecureRandom.uuid}"
  end

  ##
  # AS-6119 | Sequel makes a long-running and pointless query
  #
  # Steps:
  # 1. Confirm '/cons/business' response ok using int_xxid 471096462
  def test_consumer_business_response
    # Step 1
    get_inspectify_consumer_business_resp(471096462)
    assert_response(@response, :success)
    assert_inspectify_response(@parsed_response, :success)
  end

  ##
  # SRC-6134 | Dragon: UgcMigration: Change NonregisterUser email format validation
  #
  # Steps:
  # 1. Verify response for To/From Non Registered User email that contains '.', '_', '-', and '+'
  def test_nonregistered_user_accepted_characters
    listings = []
    response = get_consumer_search_resp
    response['SearchResult']['BusinessListings'].each do |listing|
      listings << listing['Int_Xxid']
    end

    email_check = "as.test_email-check+#{Common.random_uuid}@xx.com"

    params = {
      'request_host' => 'http://www.xx.com',
      'to' => email_check,
      'from' => email_check,
      'from_name' => 'TESTr',
      'lid' => listings.sample.to_s,
      'note' => 'Checkout this listing!',
      'mobile' => false
    }

    post '/em/share_listing', params
    assert_response(@response, :success)
    assert_match(@parsed_response['MailingID'], @parsed_response['Location'], @parsed_response)
  end

  ##
  # AS-6376 | Increase site_map timeout
  #
  # Steps:
  # 1. Verify response for sitemap is successful and within 400 ms
  def test_sitemap_successful_response_within_400_ms
    # Step 1
    params = {
      'app_id' => 'WEB',
      'vrid' => @vrid,
      'ptid' => 'inspectify',
      'o' => 600,
      'h' => 200,
      'g' => 'brecksville, oh',
      'device' => 'DESKTOP',
      'rid' => 'webyp-80a78438-c1b7-45ec-b1c4-8aa6ccc15428',
      'orig_ip' => '127.0.0.1',
      'orig_user_agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/42.0.2311.90 Safari/537.36'
    }

    inspectify_get '/site_map', params
    assert_response(@response, :success)

    @parsed_backends.each do |backend|
      if backend['name'] == 'solr_site_map'
        assert(backend['time'] <= 400, "Expecting sitemap response time to be less than or equal to 400 ms. Actual: #{backend['time']}")
      end
    end
  end

  ##
  # /cons/city returns listings that should almost always have ratings
  def test_consumer_city_returns_ratings_relatively_consistently
    # What % of listings should have ratings for this test to be considered a pass.
    passing_percent = 70.0

    params = {
      'app_id' => 'WEB',
      'vrid' => @vrid,
      'ptid' => 'inspectify',
      'rid' => @vrid,
      'g' => 'Henderson, NV'
    }

    get '/cons/city', params
    assert_response(@response, :success)

    success = 0.0
    total = 0.0

    @parsed_response['Response'].each do |modok_module|
      next unless modok_module['Type'] == 'listings'

      modok_module['Group'].each do |listing|
        total += 1
        success += 1 unless listing['Ratings'].empty?
      end
    end

    assert(total > 0, "Expected to find listings but there were none.")

    success_percent = success/total * 100

    assert(success_percent >= passing_percent, "Expected #{passing_percent}% of listings to have ratings but only #{success_percent}% did.")
  end

  ##
  # monkey's /recent endpoint should always be working
  def test_monkey_slash_recent_endpoint
    # See Email: monkey/recent constantly timing out
    skip_message = 'Dickson & Jorge are looking into monkey/recent timing out in the db: This sql took 38 seconds to run in stg and only .005 second in production.'
    assign_http(Config['monkey']['host'])

    get '/recent', {}
    skip("#{skip_message} -- #{@parsed_response['message']}") if @parsed_response['message'] =~ /Gateway\:\:GatewayTimeout/
    assert_response(@response, :success)
  end

  ##
  # Ensure AdditionalInfo array contains Label, Key, and Value for each | AS-7282
  def test_consumer_business_additional_info
    int_xxids = %w[461724648 467152316 11642174 455723303]

    businesses = []
    int_xxids.each do |int_xxid|
      get_consumer_business_resp(int_xxid)
      assert_response(@response, :success)

      businesses << @parsed_response['Business'] if @parsed_response['Business']['AdditionalInfo']
    end
    refute_empty(businesses)

    business = businesses.sample
    business['AdditionalInfo'].each do |info|
      assert(info['Label'])
      assert(info['Key'])
      refute_empty(info['Value'])
    end
  end
end
