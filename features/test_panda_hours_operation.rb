require './init'

class TestPandaHoursOfOperation < APITest

  #----------------------------------------------------------------------#
  # Panda Hours of Operation Information & Formatting:                   #
  # http://REDACTED
  #----------------------------------------------------------------------#

  def setup
    assign_http(Config["panda"]["host"])
  end

  ##
  # AS-AS-5022 | Test for OpenNow flag
  #
  # Steps:
  # 1. Validate OpenNow flag on random listings
  def test_business_open_now
    # Step 1
    random_listings_get
    log_listing = []
    time = Time.now
    @listings.each do |listing|
      local_time = nil
      offset = nil
      if listing['Timezone']
        tz = TZInfo::Timezone.get(listing['Timezone'])
        offset = tz.current_period.utc_total_offset
        local_time = time.dup.localtime(offset)
      end

      if listing['Hours'] && listing['OpenNow'] && offset
        operating = listing['Hours']['Today']['Hours'][0]

        if operating.nil?
          # TODO: Find a better solution with missing or improperly formatted hours...
          # If Text is populated, but hours missing, this means that Data couldn't
          # determine the standard hours automatically when initially imported:
          # EXAMPLE: Mon-Fri 11am-9:30pm\\nSat 4:30pm-9:30pm\\nSun 11am-9:30am
          # API will only alert an issue if this Text field is blank
          if listing['Hours']['Details'][0]['Text'].nil?
            log_listing << listing
          end
        else
          if operating[0] == 'Today' && operating[1] != 'Closed'
            # Use Rhino Data for Business Hours to determine the accuracy of the OpenNow flag that Panda provides
            default_hours = get_rhino_business_hours(listing['Int_Xxid'])
            current_day = local_time.strftime("%A")
            open_hours = default_hours['StandardHours'][current_day]
            current_time = local_time.strftime('%H%M')
            open_now = open_hours.any? { |x| current_time >= x[0] && current_time < x[1] }
            assert_equal(open_now, listing['OpenNow'], "Local Time : #{current_time}, Open - Close : #{open_hours}, Listing : #{listing}")
          else
            # 'OpenNow: nil' is a valid setting if Panda is unable to determine the
            # flag based on the hours provided by the data for the listing specified
            # EXAMPLE: The listing may only specify 'Delivery Hours'
            assert_equal(false, listing['OpenNow'], "Local Time : #{local_time}, #{operating[1]}, Listing : #{listing}") unless listing['OpenNow'].nil?
          end
        end
      end
    end

    int_xxids = []
    log_listing.each { |listing| int_xxids << listing['Int_Xxid'] }

    assert_empty(log_listing, "Please check with Data team for inaccuracies on the following Listings: #{int_xxids}" )
  end

  #------------------------------------------#
  #              Helper Methods              #
  #------------------------------------------#

  def random_listings_get(list_per_loc=3)
    @listings = []

    ['honolulu, hi', 'anchorage, ak', 'los angeles, ca', 'denver, co', 'chicago, il', 'new york, ny'].each do |loc|
      get_consumer_search_resp('restaurants', loc)
      assert_response(@response, :success)

      results = @parsed_response['SearchResult']['BusinessListings']
      skip("The BusinessListings returned are blank, please check the backend results for: restaurants + #{loc}") if results.blank?

      count = 0

      while count < list_per_loc do
        listing = results.sample

        unless @listings.detect { |x| x['Int_Xxid'] == listing['Int_Xxid'] }
          business_response = get_consumer_business_resp(listing['Int_Xxid'])
          if @response.code =~ /^2\d{2}$/
            business_check = business_response['Business']['BusinessClosedInd']

            if business_check.nil? || business_check == 0
              @listings << listing
              count += 1
            end
          end
        end
      end
    end

    @listings
  end

  def get_rhino_business_hours(int_xxid)
    assign_http(Config["rhino"]["host"])

    params = { 'q' => int_xxid }

    get '/thanos/int_xxid', params
    assert_response(@response, :success)

    default_hours = @parsed_response['results'].first['Hours']['Default']
    refute_nil(default_hours, @parsed_response)

    assign_http(Config["panda"]["host"])

    default_hours
  end
end
