module ImageHelpers
  def raw_image
    @raw_image ||= File.binread('just_do_it.jpg')
  end

  def generate_random_image
    raw_image + rand.to_s
  end

  # Returns the sha of the uploaded image
  def upload_image(oauth_token, image=nil, opts={})
    preserve_original_http(Config["monkey"]["host"]) do
      image ||= generate_random_image

      headers = { 'Content-Type' => 'image/jpg' }
      params = {
          'api_key' => Config["monkey"]["api_key"],
          'oauth_token' => oauth_token
      }.merge(opts)

      put_file "/b_image", params, image, headers
      assert_response(@response, :success)

      @parsed_response['id']
    end
  end

  def link_image(sha, ext_type, ext_id, oauth_token, opts={})
    preserve_original_http(Config["monkey"]["host"]) do
      params = {
          'ext_type' => ext_type,
          'ext_id' => ext_id,
          'oauth_token' => oauth_token,
          'api_key' => Config["monkey"]["api_key"]
      }.merge(opts)

      post "/b_image/#{sha}", params

      @response
    end
  end

  def upload_and_link_image(ext_type, ext_id, oauth_token, link_opts={})
    sha = upload_image(oauth_token)
    link_image(sha, ext_type, ext_id, oauth_token, link_opts)
    assert_response(@response, :success)

    sha
  end

  def upload_and_link_image_by_user_id(user, image=nil, caption=nil, opts={})
    preserve_original_http(Config["monkey"]["host"]) do
      return unless user && user.id && user.oauth_token

      image ||= generate_random_image
      caption ||= "Check out this picture #{user.cookie_id}"

      headers = { 'Content-Type' => 'image/jpg' }
      params = {
          'caption' => caption,
          'oauth_token' => user.oauth_token,
          'api_key' => Config["monkey"]["api_key"],
          'metadata' => {
              'user_type' => 'XX3',
              'user_id' => user.id
          }
      }.merge(opts)

      put_file "/b_image/user_id/#{user.id}/upload_and_link", params, image, headers

      @response
    end
  end

  def upload_and_link_image_for_int_xxid_by_user(int_xxid, user, image=nil, caption=nil, opts={})
    preserve_original_http(Config["monkey"]["host"]) do
      return unless int_xxid && user && user.oauth_token

      image ||= generate_random_image
      caption ||= "Check out this picture #{user.cookie_id}"

      headers = { 'Content-Type' => 'image/jpg' }
      params = {
          'caption' => caption,
          'oauth_token' => user.oauth_token,
          'api_key' => Config["monkey"]["api_key"],
          'metadata' => {
              'user_type' => 'int_xxid',
              'user_id' => int_xxid
          }
      }.merge(opts)

      put_file "/b_image/int_xxid/#{int_xxid}/upload_and_link", params, image, headers

      @response
    end
  end

  def upload_and_link_image_with_promo_for_int_xxid_by_user(int_xxid, user, promo_id, image=nil, opts={})
    preserve_original_http(Config["monkey"]["host"]) do
      return unless int_xxid && user && user.oauth_token && promo_id

      image ||= generate_random_image
      caption ||= "Check out this picture #{user.cookie_id}"

      headers = { 'Content-Type' => 'image/jpg' }
      params = {
          'caption' => caption,
          'oauth_token' => user.oauth_token,
          'api_key' => Config["monkey"]["api_key"],
          'metadata' => {
              'user_type' => 'int_xxid',
              'user_id' => int_xxid
          },
          'promo_id' => promo_id
      }.merge(opts)

      put_file "/b_image/int_xxid/#{int_xxid}/upload_and_link", params, image, headers

      @response
    end
  end

  # Accepts both a single int_xxid or an array of int_xxids
  def get_images_from_int_xxids(int_xxids, opts={})
    preserve_original_http(Config["monkey"]["host"]) do
      int_xxids = Array(int_xxids).join(",")
      params = {
          'api_key' => Config["monkey"]["api_key"]
      }.merge(opts)

      get "/b_image/int_xxid/#{int_xxids}", params
      # Can't assert_response because it could be a 200 or 404.
    end
  end

  def delete_image_from_int_xxid(sha, int_xxid)
    preserve_original_http(Config["monkey"]["host"]) do
      params = {
        'api_key'  => Config["monkey"]["api_key"],
        'reason'   => '5',
        'override' => 'true',
        'metadata' => {
          'user_type' => 'API Test',
          'user'      => 'API Test'
        }
      }

      post "/b_image/#{sha}/int_xxid/#{int_xxid}/report", params
      assert_response(@response, :success)
    end
  end

  def delete_all_images_from_int_xxid(int_xxid)
    get_images_from_int_xxids(int_xxid)
    return if @response.code == '404' # No images already

    @parsed_response['relations'].each do |relation|
      delete_image_from_int_xxid(relation['id'], int_xxid)
    end
  end
end
