module PandaHelpers
  REDACTED = 'blocked'

  def get_listings_resp(query='restaurants', geo='los angeles, ca', opts={})
    preserve_original_http(Config["panda"]["host"]) do
      params = prepare_search_params(query, geo, opts)

      get '/listings', params
    end
  end

  def get_inspectify_listings_resp(query='restaurants', geo='los angeles, ca', opts={})
    preserve_original_http(Config["panda"]["host"]) do
      params = prepare_search_params(query, geo, opts)

      inspectify_get '/listings', params
    end
  end

  def get_consumer_business_resp(int_xxid='12345', opts={})
    preserve_original_http(Config["panda"]["host"]) do
      params = { 'int_xxid' => int_xxid, }
      params.merge!(opts)

      get '/cons/business', params
    end
  end

  def get_consumer_search_resp(query='restaurants', geo='los angeles, ca', opts={})
    preserve_original_http(Config["panda"]["host"]) do
      params = prepare_search_params(query, geo, opts)

      get '/cons/search', params
    end
  end

  def get_inspectify_consumer_search_resp(query='restaurants', geo='los angeles, ca', opts={})
    preserve_original_http(Config["panda"]["host"]) do
      params = prepare_search_params(query, geo, opts)

      inspectify_get '/cons/search', params
    end
  end

  def get_inspectify_consumer_business_resp(int_xxid='12345', opts={})
    preserve_original_http(Config["panda"]["host"]) do
      params = { 'int_xxid' => int_xxid, }
      params.merge!(opts)

      inspectify_get '/cons/business', params
    end
  end

  def get_rateable_int_xxids_from_search(query='restaurants', geo='los angeles, ca', opts={})
    get_consumer_search_resp(query, geo, opts)
    assert_response(@response, :success)
    listings = nil
    @parsed_response['SearchResult']['BusinessListings'].each do |business|
      if business['Rateable'] == 1 && business['Int_Xxid']
        listings = @parsed_response['SearchResult']['BusinessListings']
      end
    end
    refute_nil(listings, "Response returned no rateable listings: #{@parsed_response['SearchResult']}")
    listings.map { |business| business['Int_Xxid'] }
  end

  def get_listings_with_coupons_from_search(query=nil, loc=nil)
    preserve_original_http(Config["panda"]["host"]) do
      query ||= ['auto','restaurants','entertainment','home','pets','shopping','pizza','furniture','contractor','plumber','spa']
      loc ||= 'los angeles, ca'

      coupon_listings = []

      Array(query).each do |query|
        params = {
            'q' => query,
            'g' => loc,
            'user_id' => @user.id,
            'rid' => '123456789',
            'vrid' => @user.vrid,
            'app_id' => 'WEB'
        }

        get '/cons/nearby', params
        assert_response(@response, :success)

        if assert(@parsed_response['Response'])
          nearby = @parsed_response['Response']
          nearby.each do |listing|
            listing['Group'].each do |group|
              if group['Coupons'] && group['Coupons'][0] && group['Coupons'][0]['CouponId']
                coupon_listings << group
              end
            end
          end
        end
      end

      coupon_listings.uniq!
      # Modok may not be returning listings, check with SearchOps/QA if this issue persists
      skip("No Listings with Coupons returned for location: #{loc} & query: #{query}") if coupon_listings.empty?

      coupon_listings
    end
  end

  # Returns the rating's id
  def review_business(int_xxid, oauth_token, extra_params={})
    preserve_original_http(Config["panda"]["host"]) do
      params = {
        'body' => 'This business is very business-like and I would do business with this business again if I have business with them.',
        'source' => 'CSE',
        'subject' => 'Review made by API',
        'value' => 3,
        'int_xxid' => int_xxid,
        'oauth_token' => oauth_token
      }.merge(extra_params)

      post '/rats/add_rating', params

      assert_response(@response, :success)

      @parsed_response['RatingID']
    end
  end

  # copied from '$panda/lib/mb > self.decode_keys'
  def decode_keys_mb(unique_collection_id)
    encoded_composed_key = unique_collection_id.split('-').last
    fix_encoded_composed_key = encoded_composed_key.gsub('!', '-')
    decoded_data = REDACTED(fix_encoded_composed_key)

    owner_collection_id, owner_id = decoded_data.split('~')

    {
        'owner_collection_id' => owner_collection_id,
        'owner_id' => owner_id
    }
  end

  def lookup_user_by_id(id=nil)
    preserve_original_http(Config["panda"]["host"]) do
      return nil unless id

      params = { 'id' => id }

      get '/usr/lookup', params
      assert_response(@response, :success)

      @parsed_response
    end
  end

  def lookup_user_by_email(email=nil)
    preserve_original_http(Config["panda"]["host"]) do
      return nil unless email

      params = { 'email' => email }

      get '/usr/lookup', params
      assert_response(@response, :success)

      @parsed_response
    end
  end

  def get_nonregisterd_user(email=nil)
    preserve_original_http(Config["panda"]["host"]) do
      return nil unless email

      get "/nonregistered_users/#{email}", {}
      assert_response(@response, :success)

      @parsed_response
    end
  end

  def delete_all_reviews_for_user_by_id(user_id=nil)
    preserve_original_http(Config["panda"]["host"]) do
      return nil unless user_id

      params = { 'user_id' => user_id }

      get '/rats', params
      assert_response(@response, :success)

      deleted_ids = []
      unless @parsed_response.blank?
        @parsed_response.each do |rating|
          delete "/rats/#{rating['id']}", {}
          deleted_ids << rating['id'] if @response.code =~ /^2\d{2}$/
        end
      end

      deleted_ids
    end
  end

  def get_valid_article_queries
    preserve_original_http(Config["panda"]["host"]) do
      article_categories = []

      get '/articles', {}
      assert_response(@response, :success)
      refute_empty(@parsed_response['Articles'])
      @parsed_response['Articles'].each do |article|
        unless article['BraftonCategories'].blank?
          article['BraftonCategories'].each do |category|
            article_categories << category
          end
        end
      end

      article_categories.uniq!
    end
  end

  private

  def default_params
    {
        'app_id' => 'WEB',
        'ptid' => 'API_OMG',
        'vrid' => 'API_ABC',
        'rid' => 'API_123'
    }
  end

  def prepare_search_params(query, geo, opts)
    params = {
        'q' => query,
        'g' => geo,
    }

    params.merge(default_params).merge(opts)
  end
end
