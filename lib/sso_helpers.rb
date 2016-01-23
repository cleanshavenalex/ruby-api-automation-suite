module SSOHelpers
  def update_sso_session(hash)
    if @last_session
      hash['Cookie'] = "_sso_server_session=#{@last_session}"
    else
      session = CGI::Cookie.parse(@response['set-cookie'])['_sso_server_session'].first
      if session.present?
        @last_session = CGI.escape(session)
        hash['Cookie'] = "_sso_server_session=#{CGI.escape(session)}"
      else
        session = CGI::Cookie.parse(@response['cookie'])['_sso_server_session'].first
        if session.present?
          @last_session = CGI.escape(session)
          hash['Cookie'] = "_sso_server_session=#{CGI.escape(session)}"
        end
      end
    end
  end

  def get_sso_csrf
    Nokogiri::HTML(@response.body).
        css("head meta[name=csrf-token]").
        attribute('content').
        content
  end

  # The path needs to be constructed with the params already
  def get_with_sso_credentials path, headers={}
    get path, {}, headers
    assert_response(@response, :redirect)

    redirect_path = URI.parse(@response['location']).request_uri

    update_session_in(headers)

    get redirect_path, {}, headers
    assert_response(@response, :redirect)

    redirect_uri = URI.parse(@response['location'])
    redirect_query = redirect_uri.query
    service = CGI.parse(redirect_query)['service'].first

    sso_response = @sso_user.login(service)
    assert_response(sso_response, :success)

    redirect_uri = URI.parse(sso_response['location'])
    redirect_path = redirect_uri.request_uri

    update_session_in(headers)

    get redirect_path, {}, headers
    assert_response(@response, :redirect)

    redirect_path = URI.parse(@response['location']).request_uri

    update_session_in(headers)

    get redirect_path, {}, headers
    assert_response(@response, :success)

    @latest_headers = headers

    @parsed_response
  end
end
