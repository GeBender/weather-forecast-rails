require "test_helper"

class ForecastsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get forecasts_index_url
    assert_response :success
  end
end
