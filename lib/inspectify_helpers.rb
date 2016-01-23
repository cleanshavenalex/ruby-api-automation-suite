module InspectifyHelpers
  def inspectify_get(path, params, headers={})
    path = "/inspectify" + path
    params["format"] = "json"

    get path, params, headers

    @parsed_backends = parse_backends if @parsed_response
  end

  private

  def parse_backends
    @parsed_response["backend"].map do |backend|
      {
        "name"        => backend[0],
        "time"        => backend[1],
        "status"      => backend[2],
        "status_text" => backend[3],
        "request"     => backend[4]
      }
    end
  end
end
