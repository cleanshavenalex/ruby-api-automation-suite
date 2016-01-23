module PromoHelpers
  PROMO_HEADINGS = ['Child Care','Restaurants','Art Supplies','Attorneys','Medical Clinics','Orthodontists','Mortgages']

  def get_promo_heading
    PROMO_HEADINGS.sample
  end

  def unique_promo_code
    "App_Services_Rules_#{Common.random_uuid}"
  end

  def unique_moderator_id
    moderator = ['Tony_Stark','Peter_Parker','Bruce_Banner','Bruce_Wayne','Clark_Kent','Wade_Wilson','Steve_Rodgers'].sample
    "#{moderator}_#{Common.random_uuid}"
  end

  def get_promo_with_code(promo_code=nil)
    preserve_original_http(Config['panda']['host']) do
      return unless promo_code

      get '/pros', {}
      assert_response(@response, :success)
      promo = @parsed_response['Promos'].find { |promo| promo['Code'] == promo_code }

      skip("Warning: Unable to locate #{promo_code} within /pros response") if promo.nil?

      promo
    end
  end

  def get_all_promos_with_partial_code(promo_code=nil, is_deleted=0)
    preserve_original_http(Config['panda']['host']) do
      return unless promo_code

      get '/pros', {}
      assert_response(@response, :success)
      promos = []
      @parsed_response['Promos'].each do |promo|
        promos << promo if promo['Code'] =~ Regexp.new(promo_code) && promo['Deleted'] == is_deleted
      end

      promos
    end
  end

  def get_promo_points(promo_id=nil, opts={})
    preserve_original_http(Config['panda']['host']) do
      return unless promo_id

      params = { 'promo_id' => promo_id }
      params.merge(opts) unless opts.blank?

      get '/pros/addon_points', params
      assert_response(@response, :success)
      assert(@parsed_response['PromoAddonPoints'])
      addon_points = @parsed_response['PromoAddonPoints']

      get '/pros/points', params
      assert_response(@response, :success)
      assert(@parsed_response['ReviewPoints'])
      assert(@parsed_response['PhotoPoints'])
      points = @parsed_response

      get '/pros/base_points', params
      assert_response(@response, :success)
      assert(@parsed_response['PromoPoints'])
      base_points = @parsed_response['PromoPoints']

      get '/pros/multipliers', params
      assert_response(@response, :success)
      assert(@parsed_response['PromoMultipliers'])
      multipliers = @parsed_response['PromoMultipliers']

      get '/pros/points_to_price', params
      assert_response(@response, :success)
      assert(@parsed_response['PointsToPrices'])
      points_to_prices = @parsed_response['PointsToPrices']

      {
          'addon_points' => addon_points,
          'points' => points,
          'base_points' => base_points,
          'multipliers' => multipliers,
          'points_to_price' => points_to_prices
      }
    end
  end

  def get_promo_listings(query=nil, loc='Glendale, CA', opts={})
    preserve_original_http(Config['panda']['host']) do
      query ||= get_promo_heading
      get_consumer_search_resp(query, loc, opts)
      assert_response(@response, :success)

      listings = @parsed_response['SearchResult']['BusinessListings']
      refute_empty(listings, "No search results found for #{query}, g=#{loc}")

      listings.delete_if do |business|
        !business['AllHeadings'].find { |heading| heading == query } ||
            business['Rateable'] != 1
      end

      skip("No listings returned matching parameters within delete_if: #{query}") if listings.empty?

      listings
    end
  end

  def get_promo_points_for_business(int_xxid=nil, promo_code='APIACTIVEPROMO')
    preserve_original_http(Config['panda']['host']) do
      return unless int_xxid

      # promo points
      promo = get_promo_with_code(promo_code)
      promo_points = get_promo_points(promo['Id'])
      assert(promo_points['base_points'])
      assert(promo_points['multipliers'])
      assert(promo_points['addon_points'])

      # business
      get_consumer_business_resp(int_xxid)
      assert_response(@response, :success)
      refute_nil(@parsed_response['Business'])
      business = @parsed_response['Business']
      promo_uber_cats = business['PromoUbercats'].split('|') if business['PromoUbercats']

      # defaults
      review_points = 0
      photo_points = 0
      review_multiplier = 1
      photo_multiplier = 1
      review_addon_points = 0
      photo_addon_points = 0

      # base points
      business['AllHeadingCodes'].each do |ahc|
        base_check = promo_points['base_points'].find { |bp| bp['GroupHeadingCode'] == ahc }
        if base_check
          if base_check['ReviewPoints']
            if base_check['ReviewPoints'] > review_points
              review_points = base_check['ReviewPoints']
            end
          end
          if base_check['PhotoPoints']
            if base_check['PhotoPoints'] > photo_points
              photo_points = base_check['PhotoPoints']
            end
          end
        end

        base_check = promo_points['base_points'].find { |bp| bp['HeadingCode'] == ahc }
        if base_check
          if base_check['ReviewPoints']
            if base_check['ReviewPoints'] > review_points
              review_points = base_check['ReviewPoints']
            end
          end
          if base_check['PhotoPoints']
            if base_check['PhotoPoints'] > photo_points
              photo_points = base_check['PhotoPoints']
            end
          end
        end

        multiplier_check = promo_points['multipliers'].find { |m| m['GroupHeadingCode'] == ahc }
        if multiplier_check
          if multiplier_check['ReviewMultiplier'] && multiplier_check['Status'] == 'Live'
            if multiplier_check['ReviewMultiplier'] > review_multiplier
              review_multiplier = multiplier_check['ReviewMultiplier']
            end
          end
          if multiplier_check['PhotoMultiplier'] && multiplier_check['Status'] == 'Live'
            if multiplier_check['PhotoMultiplier'] > photo_multiplier
              photo_multiplier = multiplier_check['PhotoMultiplier']
            end
          end
        end

        multiplier_check = promo_points['multipliers'].find { |m| m['HeadingCode'] == ahc }
        if multiplier_check
          if multiplier_check['ReviewMultiplier'] && multiplier_check['Status'] == 'Live'
            if multiplier_check['ReviewMultiplier'] > review_multiplier
              review_multiplier = multiplier_check['ReviewMultiplier']
            end
          end
          if multiplier_check['PhotoMultiplier'] && multiplier_check['Status'] == 'Live'
            if multiplier_check['PhotoMultiplier'] > photo_multiplier
              photo_multiplier = multiplier_check['PhotoMultiplier']
            end
          end
        end

        addon_check = promo_points['addon_points'].find { |ap| ap['GroupHeadingCode'] == ahc }
        if addon_check
          if addon_check['ReviewAddonPoints'] && addon_check['Status'] == 'Live'
            if addon_check['ReviewAddonPoints'] > review_addon_points
              review_addon_points = addon_check['ReviewAddonPoints']
            end
          end
          if addon_check && addon_check['PhotoAddonPoints'] && addon_check['Status'] == 'Live'
            if addon_check['PhotoAddonPoints'] > photo_addon_points
              photo_addon_points = addon_check['PhotoAddonPoints']
            end
          end
        end

        addon_check = promo_points['addon_points'].find { |ap| ap['HeadingCode'] == ahc }
        if addon_check
          if addon_check['ReviewAddonPoints'] && addon_check['Status'] == 'Live'
            if addon_check['ReviewAddonPoints'] > review_addon_points
              review_addon_points = addon_check['ReviewAddonPoints']
            end
          end
          if addon_check && addon_check['PhotoAddonPoints'] && addon_check['Status'] == 'Live'
            if addon_check['PhotoAddonPoints'] > photo_addon_points
              photo_addon_points = addon_check['PhotoAddonPoints']
            end
          end
        end
      end

      # uber cat
      if promo_uber_cats
        if review_points == 0
          promo_points['base_points'].each do |bp|
            if bp['HeadingCode'].nil? && bp['GroupHeadingCode'].nil?
              if bp['ReviewPoints'] && promo_uber_cats.include?(bp['UberCat'])
                if bp['ReviewPoints'] > review_points
                  review_points = bp['ReviewPoints']
                end
              end
            end
          end
        end

        if photo_points == 0
          promo_points['base_points'].each do |bp|
            if bp['HeadingCode'].nil? && bp['GroupHeadingCode'].nil?
              if bp['PhotoPoints'] && promo_uber_cats.include?(bp['UberCat'])
                if bp['PhotoPoints'] > photo_points
                  photo_points = bp['PhotoPoints']
                end
              end
            end
          end
        end

        if review_multiplier == 1
          promo_points['multipliers'].each do |m|
            if m['HeadingCode'].nil? && m['GroupHeadingCode'].nil?
              if m['ReviewMultiplier'] && promo_uber_cats.include?(m['UberCat']) && m['Status'] == 'Live'
                if m['ReviewMultiplier'] > review_multiplier
                  review_multiplier = m['ReviewMultiplier']
                end
              end
            end
          end
        end

        if photo_multiplier == 1
          promo_points['multipliers'].each do |m|
            if m['HeadingCode'].nil? && m['GroupHeadingCode'].nil?
              if m['PhotoMultiplier'] && promo_uber_cats.include?(m['UberCat']) && m['Status'] == 'Live'
                if m['PhotoMultiplier'] > photo_multiplier
                  photo_multiplier = m['PhotoMultiplier']
                end
              end
            end
          end
        end

        if review_addon_points == 0
          promo_points['addon_points'].each do |ap|
            if ap['HeadingCode'].nil? && ap['GroupHeadingCode'].nil?
              if ap['ReviewAddonPoints'] && promo_uber_cats.include?(ap['UberCat']) && ap['Status'] == 'Live'
                if ap['ReviewAddonPoints'] > review_addon_points
                  review_addon_points = ap['ReviewAddonPoints']
                end
              end
            end
          end
        end

        if photo_addon_points == 0
          promo_points['addon_points'].each do |ap|
            if ap['HeadingCode'].nil? && ap['GroupHeadingCode'].nil?
              if ap['PhotoAddonPoints'] && promo_uber_cats.include?(ap['UberCat']) && ap['Status'] == 'Live'
                if ap['PhotoAddonPoints'] > photo_addon_points
                  photo_addon_points = ap['PhotoAddonPoints']
                end
              end
            end
          end
        end
      end

      # category type
      if review_points == 0
        promo_points['base_points'].each do |bp|
          if bp['HeadingCode'].nil? && bp['GroupHeadingCode'].nil?
            if bp['ReviewPoints'] && bp['CategoryType'] == business['CategoryType']
              if bp['ReviewPoints'] && bp['ReviewPoints'] > review_points
                review_points = bp['ReviewPoints']
              end
            end
          end
        end
      end

      if photo_points == 0
        promo_points['base_points'].each do |bp|
          if bp['HeadingCode'].nil? && bp['GroupHeadingCode'].nil?
            if bp['PhotoPoints'] && bp['CategoryType'] == business['CategoryType']
              if bp['PhotoPoints'] > photo_points
                photo_points = bp['PhotoPoints']
              end
            end
          end
        end
      end

      if review_multiplier == 1
        promo_points['multipliers'].each do |m|
          if m['HeadingCode'].nil? && m['GroupHeadingCode'].nil?
            if m['ReviewMultiplier'] && m['CategoryType'] == business['CategoryType'] && m['Status'] == 'Live'
              if m['ReviewMultiplier'] > review_multiplier
                review_multiplier = m['ReviewMultiplier']
              end
            end
          end
        end
      end

      if photo_multiplier == 1
        promo_points['multipliers'].each do |m|
          if m['HeadingCode'].nil? && m['GroupHeadingCode'].nil?
            if m['PhotoMultiplier'] && m['CategoryType'] == business['CategoryType'] && m['Status'] == 'Live'
              if m['PhotoMultiplier'] > photo_multiplier
                photo_multiplier = m['PhotoMultiplier']
              end
            end
          end
        end
      end

      if review_addon_points == 0
        promo_points['addon_points'].each do |ap|
          if ap['HeadingCode'].nil? && ap['GroupHeadingCode'].nil?
            if ap['ReviewAddonPoints'] && ap['CategoryType'] == business['CategoryType'] && ap['Status'] == 'Live'
              if ap['ReviewAddonPoints'] > review_addon_points
                review_addon_points = ap['ReviewAddonPoints']
              end
            end
          end
        end
      end

      if photo_addon_points == 0
        promo_points['addon_points'].each do |ap|
          if ap['HeadingCode'].nil? && ap['GroupHeadingCode'].nil?
            if ap['PhotoAddonPoints'] && ap['CategoryType'] == business['CategoryType'] && ap['Status'] == 'Live'
              if ap['PhotoAddonPoints'] > photo_addon_points
                photo_addon_points = ap['PhotoAddonPoints']
              end
            end
          end
        end
      end

      review_bonus = false
      review = ((review_points * review_multiplier) + review_addon_points).ceil
      if business['Ratings'].empty? && business['RatingCount'] == 0
        review += promo['FirstReviewBonusPoints'] || 0
        review_bonus = true
      end

      photo_bonus = false
      photo = ((photo_points * photo_multiplier) + photo_addon_points).ceil
      if business['Media']['Data'].empty? && business['Media']['TotalCount'] == 0
        photo += promo['FirstPhotoBonusPoints'] || 0
        photo_bonus = true
      end

      {
          'review_points' => review,
          'photo_points' => photo,
          'details' => {
              'int_xxid' => int_xxid,
              'review' => {
                  'base_points' => review_points.ceil,
                  'multiplier' => review_multiplier,
                  'addon_points' => review_addon_points.ceil,
                  'first_review_bonus' => review_bonus
              },
              'photo' => {
                  'base_points' => photo_points.ceil,
                  'multiplier' => photo_multiplier,
                  'addon_points' => photo_addon_points.ceil,
                  'first_photo_bonus' => photo_bonus
              }
          }
      }
    end
  end

  def add_base_points_for_promo(promo_id=nil, points_hash={})
    preserve_original_http(Config['panda']['host']) do
      return unless promo_id

      params = {
          'promo_points' => [
              {
                  'promo_id' => promo_id,
                  'review_points' => 70,
                  'photo_points' => 35,
                  'heading_code' => '8000149',
                  'heading_text' => 'Art Supplies',
                  'display_category_name' => 'Art Supplies',
                  'points_tier' => 2
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 70,
                  'photo_points' => 35,
                  'heading_code' => '8000177',
                  'heading_text' => 'Attorneys',
                  'display_category_name' => 'Attorneys',
                  'points_tier' => 2
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 70,
                  'photo_points' => 35,
                  'heading_code' => '8010900',
                  'heading_text' => 'Child Care',
                  'display_category_name' => 'Child Care',
                  'points_tier' => 2
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 100,
                  'photo_points' => 50,
                  'heading_code' => '8000799',
                  'heading_text' => 'Medical Clinics',
                  'display_category_name' => 'Medical Clinics',
                  'points_tier' => 1
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 100,
                  'photo_points' => 50,
                  'heading_code' => '8005219',
                  'heading_text' => 'Orthodontists',
                  'display_category_name' => 'Orthodontists',
                  'points_tier' => 1
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 30,
                  'photo_points' => 15,
                  'heading_code' => '8009371',
                  'heading_text' => 'Restaurants',
                  'display_category_name' => 'Restaurants',
                  'points_tier' => 3
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 70,
                  'photo_points' => 35,
                  'heading_code' => '8016124',
                  'heading_text' => 'Asian Restaurants',
                  'display_category_name' => 'Asian Restaurants',
                  'points_tier' => 2,
                  'group_heading_code' => '8016124',
                  'group_heading_text' => 'Asian Restaurants'
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 80,
                  'photo_points' => 40,
                  'heading_code' => '8004214',
                  'heading_text' => 'Japanese Restaurants',
                  'display_category_name' => 'Japanese Restaurants',
                  'points_tier' => 2,
                  'group_heading_code' => '8004214',
                  'group_heading_text' => 'Japanese Restaurants'
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 70,
                  'photo_points' => 35,
                  'heading_code' => '8009623',
                  'heading_text' => 'Mortgages',
                  'display_category_name' => 'Mortgages',
                  'points_tier' => 2
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 30,
                  'photo_points' => 15,
                  'heading_text' => 'Service',
                  'display_category_name' => 'Service',
                  'points_tier' => 3
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 30,
                  'photo_points' => 15,
                  'heading_text' => 'Discovery',
                  'display_category_name' => 'Discovery',
                  'points_tier' => 3
              },
              {
                  'promo_id' => promo_id,
                  'review_points' => 30,
                  'photo_points' => 15,
                  'heading_text' => 'Utility',
                  'display_category_name' => 'Utility',
                  'points_tier' => 3
              },
          ]
      }
      params['promo_points'] << points_hash unless points_hash.blank?

      post '/pros/points/multi', params

      @response
    end
  end

  def create_new_promo(opts={})
    preserve_original_http(Config['panda']['host']) do
      code = opts['code'] || unique_promo_code
      name = opts['name'] || "ASQA_PROMO_#{Common.random_uuid}"
      org_name = opts['org_name'] || 'ASQA_PROMO'
      city = opts['city'] || 'Glendale'
      state = opts['state'] || 'CA'
      timezone = opts['timezone'] || 'America/Los_Angeles'
      team_names = opts['team_names'] || ['Red','Blue','Green','Yellow','Orange','Purple']
      team_type = opts['team_type'] || 'Color'
      start_date = opts['start_date'] || (Time.now + 1.day).to_i
      end_date = opts['end_date'] || (Time.now + rand(10..20).day).to_i
      default_attributes = opts['default_attributes'] || 'Parent:true|Homeowner:true|Pet Owner:false|Business Owner:false'

      params = {
          'code' => code,
          'name' => name,
          'org_name' => org_name,
          'city' => city,
          'state' => state,
          'timezone' => timezone,
          'team_names' => team_names,
          'team_type' => team_type,
          'start_date' => start_date,
          'end_date' => end_date,
          'default_attributes' => default_attributes,
      }
      params['lsa'] = opts['lsa'] if opts['lsa']
      params['first_photo_bonus_points'] = opts['first_photo_bonus_points'] if opts['first_photo_bonus_points']
      params['first_review_bonus_points'] = opts['first_review_bonus_points'] if opts['first_review_bonus_points']
      params['multiplier'] = opts['multiplier'] if opts['multiplier']
      params['multiplier_start_date'] = opts['multiplier_start_date'] if opts['multiplier_start_date']
      params['new_listing_itl_points'] = opts['new_listing_itl_points'] if opts['new_listing_itl_points']
      params['update_listing_itl_points'] = opts['update_listing_itl_points'] if opts['update_listing_itl_points']

      post '/pros', params

      @response
    end
  end

  # By Default this will deletes all matching created promos from API tests
  def delete_matching_promos(matching_promo_code='App_Services_Rules_')
    preserve_original_http(Config['panda']['host']) do
      promos = get_all_promos_with_partial_code(matching_promo_code)

      unless promos.blank?
        promos.each do |promo|
          params = { 'promo_id' => promo['Id'] }
          delete '/pros', params
        end
      end
    end
  end
end
