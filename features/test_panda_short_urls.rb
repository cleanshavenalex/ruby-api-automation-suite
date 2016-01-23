require './init'

class TestPandaShortURLs < APITest
  def setup
    assign_http(Config["panda"]["host"])
  end

  ##
  # AS-6019 | API Test for ShortURL
  # - POST to /shorturls
  #
  # steps:
  # 1. Post a long panda url to /shorturls endpoint
  # 2. Confirm response parameters & contains a code
  # 3. Using the array of stored codes, GET the urls with /shorturls/redirect/:code,
  #    also confirm response parameters for each & each contains the posted url
  def test_creating_short_urls_app_url
    unique_identifier = Common.random_uuid
    xx = "http://dev-panda.int.xx.com/#{unique_identifier}/cons/search?allow_closed_businesses=true&app_id=MOB&chain_collapse=true&h=6&img_paths=true&lat=34.155125&limit=10&lon=-118.256721&o=0&offset=0&prof=yp46&ptid=Inspectify&q=plumber&record_history=true&rid=11FEC292-7E8B-42EA-8D17-49B0CEDDDDC2&sponsored_results=0&vrid=afc17057251c56c3dd5763be294ce473"

    # Step 1
    params = {
        'shorturl' => {
            'url' => xx
        }
    }

    post '/shorturls', params
    assert_response(@response, :success)

    # Step 2
    assert(@parsed_response['code'], @parsed_response)
    assert_equal(params['shorturl']['url'], @parsed_response['url'], @parsed_response)

    # Step 3
    get "/shorturls/redirect/#{@parsed_response['code']}", {}
    assert_response(@response, :redirect)
    assert_equal(xx, @response['Location'])
  end

  ##
  # AS-6019 | API Test for ShortURL
  # - POST to /shorturls
  #
  # steps:
  # 1. Post a long panda url to /shorturls endpoint
  # 2. Confirm response parameters & contains a code
  # 3. Post the exact same long app url to /shorturls endpoint
  # 4. Confirm response parameters & contains the same exact code from the previous response
  # 5. Using the array of stored codes, GET the urls with /shorturls/redirect/:code,
  #    also confirm response parameters for each & each contains the posted url
  def test_duplicate_app_url
    unique_identifier = Common.random_uuid
    xx = "http://dev-panda.int.xx.com/#{unique_identifier}/cons/search?allow_closed_businesses=true&app_id=MOB&chain_collapse=true&h=6&img_paths=true&lat=34.155125&limit=10&lon=-118.256721&o=0&offset=0&prof=yp46&ptid=Inspectify&q=plumber&record_history=true&rid=11FEC292-7E8B-42EA-8D17-49B0CEDDDDC2&sponsored_results=0&vrid=afc17057251c56c3dd5763be294ce473"

    # Step 1
    params = {
        'shorturl' => {
            'url' => xx
        }
    }

    post '/shorturls', params
    assert_response(@response, :success)

    # Step 2
    assert(@parsed_response['code'], @parsed_response)
    assert_equal(params['shorturl']['url'], @parsed_response['url'], @parsed_response)

    shorturl_code = @parsed_response['code']

    # Step 3
    post '/shorturls', params
    assert_response(@response, :success)

    # Step 4
    assert(@parsed_response['code'], @parsed_response)
    assert_equal(params['shorturl']['url'], @parsed_response['url'], @parsed_response)
    assert_equal(shorturl_code, @parsed_response['code'], @parsed_response)

    # Step 5
    get "/shorturls/redirect/#{@parsed_response['code']}", {}
    assert_response(@response, :redirect)
    assert_equal(xx, @response['Location'])
  end

  ##
  # AS-6019 | API Test for ShortURL
  # - POST to /shorturls
  #
  # steps:
  # 1. Post non-xx ssl url to /shorturls endpoint
  # 2. Confirm response parameters & contains a code
  # 3. Using the array of stored codes, GET the urls with /shorturls/redirect/:code,
  #    also confirm response parameters for each & each contains the posted url
  def test_creating_short_urls_ssl
    unique_identifier = Common.random_uuid
    ssl = "https://graph.facebook.com/#{unique_identifier}"

    # Step 1
    params = {
        'shorturl' => {
            'url' => ssl
        }
    }

    post '/shorturls', params
    assert_response(@response, :success)

    # Step 2
    assert(@parsed_response['code'], @parsed_response)
    assert_equal(params['shorturl']['url'], @parsed_response['url'], @parsed_response)

    shorturl_code = @parsed_response['code']

    # Step 3
    get "/shorturls/redirect/#{shorturl_code}", {}
    assert_response(@response, :redirect)
    assert_equal(ssl, @response['Location'])
  end

  ##
  # AS-6019 | API Test for ShortURL
  # - POST to /shorturls
  #
  # steps:
  # 1. Post non-xx url to /shorturls endpoint
  # 2. Confirm response parameters & contains a code
  # 3. Using the array of stored codes, GET the urls with /shorturls/redirect/:code,
  #    also confirm response parameters for each & each contains the posted url
  def test_creating_short_urls_non_app_url
    unique_identifier = Common.random_uuid
    url = "http://www.google.com/#{unique_identifier}"

    # Step 1
    params = {
        'shorturl' => {
            'url' => url
        }
    }

    post '/shorturls', params
    assert_response(@response, :success)

    # Step 2
    assert(@parsed_response['code'], @parsed_response)
    assert_equal(params['shorturl']['url'], @parsed_response['url'], @parsed_response)

    # Step 3
    get "/shorturls/redirect/#{@parsed_response['code']}", {}
    assert_response(@response, :redirect)
    assert_equal(url, @response['Location'])
  end

  ##
  # AS-6019 | API Test for ShortURL
  # - POST to /shorturls
  #
  # steps:
  # 1. Confirm POST with incorrect parameters returns 400 Response & appropriate errors
  # 2. Confirm POST with blank parameters returns 400 Response & appropriate errors
  def test_short_urls_error_response
    # Step 1
    params = {
        'shorturl' => {
            'url' => 'invalid-url.com'
        }
    }

    post '/shorturls', params
    assert_response(@response, :client_error)
    assert_equal('ShorturlError', @parsed_response['error'], @parsed_response)
    assert_equal('url is invalid', @parsed_response['message'], @parsed_response)

    # Step 2
    params = {
        'shorturl' => {
            'url' => ''
        }
    }

    post '/shorturls', params
    assert_response(@response, :client_error)
    assert_equal('ShorturlError', @parsed_response['error'], @parsed_response)
    assert_equal('url is not present, url is invalid', @parsed_response['message'], @parsed_response)
  end

  ##
  # AS-6019 | API Test for ShortURL
  # - POST to /shorturls
  #
  # steps:
  # 1. Request using an invalid code, and confirm xx.com is returned
  def test_short_url_unknown_code_default
    # Step 1
    get "/shorturls/redirect/OMGOMG", {}
    assert_response(@response, :redirect)
    assert_equal('http://www.xx.com', @response['Location'])
  end
end
