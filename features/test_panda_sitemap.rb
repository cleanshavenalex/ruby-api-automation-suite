require './init'

class TestPandaSitemap < APITest
  def setup
    assign_http(Config["panda"]["host"])
  end

  ##
  # AS-6150 | SEO: Endpoint for top KBSM Queries
  #
  # Steps
  # 1. Verify response for geo and queries parameters set to 0
  # 2. Verify response for geo and queries parameters set to 10 & 30 respectively
  # 3. Verify response for geo and queries parameters set to 50 & 100 respectively
  # 4. Verify response returned default of 50 for geo and queries parameters missing
  # 5. Verify response returs 50 & 100 for geo and queries parameters set to 100 & 1000 respectively
  def test_sitemap_geos_and_queries
    geos = ['ca', 'co', 'il', 'ny']

    geos.each do |loc|
      # Step 1
      params = {
          'g' => loc,
          'h_geos' => 0,
          'h_queries' => 0
      }

      get '/site_map/geos_and_queries', params
      assert_response(@response, :success)
      assert_equal(0, @parsed_response['Geos']['NumFound'], @parsed_response)
      assert_equal(0, @parsed_response['Queries']['NumFound'], @parsed_response)

      # Step 2
      params = {
          'g' => loc,
          'h_geos' => 10,
          'h_queries' => 30
      }

      get '/site_map/geos_and_queries', params
      assert_response(@response, :success)
      assert_equal(10, @parsed_response['Geos']['NumFound'], @parsed_response)
      assert_equal(30, @parsed_response['Queries']['NumFound'], @parsed_response)

      # Step 3
      params = {
          'g' => loc,
          'h_geos' => 50,
          'h_queries' => 100
      }

      get '/site_map/geos_and_queries', params
      assert_response(@response, :success)
      assert_equal(50, @parsed_response['Geos']['NumFound'], @parsed_response)
      assert_equal(100, @parsed_response['Queries']['NumFound'], @parsed_response)

      # Step 4
      params = {
          'g' => loc
      }

      get '/site_map/geos_and_queries', params
      assert_response(@response, :success)
      assert_equal(50, @parsed_response['Geos']['NumFound'], @parsed_response)
      assert_equal(50, @parsed_response['Queries']['NumFound'], @parsed_response)

      # Step 5
      params = {
          'g' => loc,
          'h_geos' => 100,
          'h_queries' => 1000
      }

      get '/site_map/geos_and_queries', params
      assert_response(@response, :success)
      assert_equal(50, @parsed_response['Geos']['NumFound'], @parsed_response)
      assert_equal(100, @parsed_response['Queries']['NumFound'], @parsed_response)
    end
  end

  ##
  # AS-6382 | Return empty array when there are no results in sitemap
  #
  # Steps:
  # 1. Verify response for unknown location returns empty array for results
  def test_site_map_returns_empty_array_for_no_results
    # Step 1
    params = {
        'g' => 'ko',
        'n' => 10,
        'start' => 1
    }

    get '/site_map', params
    assert_response(@response, :success)
    assert_equal(0, @parsed_response['NumFound'], @parsed_response)
    assert_empty(@parsed_response['Results'], @parsed_response)
    assert_equal(0, @parsed_response['Count'], @parsed_response)
  end

  def test_sitemap_response_format
    get '/site_map', 'g' => 'Tallahassee, FL'
    assert_response(@response, :success)

    results = @parsed_response['Results']
    refute_nil(results)

    expected_keys = ['Geo', 'Term', 'Priority', 'Display', 'Frequency']
    results.each do |result|
      assert_equal(expected_keys, result.keys)
    end
  end
end
