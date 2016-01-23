require './init'

class TestPandaDbCheck < APITest
  def setup
    assign_http(Config["panda"]["host"])
  end

  def test_panda_db_check_status_ok
    params = {}

    get '/_priv/models/check', params
    assert_response(@response, :success)
    assert_equal('OK', @response.message, "Warning : #{@response.body}, #{@response.message} ")
  end
end
