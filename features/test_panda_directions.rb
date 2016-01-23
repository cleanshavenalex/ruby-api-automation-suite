require './init'

class TestPandaDirections < APITest

  DIRECTIONS_KEYS = {
      main: ['Itinerary', 'TotalDistance', 'TotalDrivingTime'],
      itinerary: ['Action', 'Distance', 'Duration', 'Instruction', 'Latitude', 'Longitude']
  }

  def setup
    assign_http(Config["panda"]["host"])
  end

  ##
  # AS-6200 | Integrate with Google, check directions response
  #
  # Steps:
  # 1. Verify response & parameters for directions for basic start & stop lat & lon
  def test_directions_for_start_end_lat_lon
    # Step 1
    params = {
        'start_lat' => 34.155,
        'start_lon' => -118.255,
        'end_lat' => 34.16,
        'end_lon' => -118.42
    }

    get '/directions', params
    assert_response(@response, :success)
    assert_has_keys(@parsed_response, DIRECTIONS_KEYS[:main])
    @parsed_response['Itinerary'].each do |itinerary|
      assert_has_keys(itinerary, DIRECTIONS_KEYS[:itinerary])
    end

    total_distance = get_total_distance(@parsed_response['Itinerary'])
    refute_nil(@parsed_response['TotalDistance'], @parsed_response)
    assert_in_epsilon(total_distance, @parsed_response['TotalDistance'], 0.001, @parsed_response)
    refute_nil(@parsed_response['TotalDrivingTime'], @parsed_response)
    assert(@parsed_response['TotalDrivingTime'] > 0, @parsed_response)
  end

  #------------------------------------------#
  #              Helper Methods              #
  #------------------------------------------#

  def get_total_distance(itinerary)
    distance_sum = 0

    itinerary.each do |step_hash|
      step_hash.each do |key, value|
        if key == 'Distance'
          distance_sum += value
        end
      end
    end

    distance_sum
  end
end
