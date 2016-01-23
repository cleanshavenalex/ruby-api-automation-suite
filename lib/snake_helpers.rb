module SnakeHelpers
  def get_snake_consumer_business_resp(opts)
    preserve_original_http(Config["snake"]["host"]) do
      path = '/snake/cons/business'

      params = {
        'api_key' => @api_key,
        'vrid' => @user.vrid,
        'int_xxid' => 481321326,
        'prof' => opts['prof']
      }

      get path, params, opts
    end
  end
end
