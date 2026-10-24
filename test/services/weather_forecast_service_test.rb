require "test_helper"
require "net/http"
require "socket"

class WeatherForecastServiceTest < ActiveSupport::TestCase
  class SuccessfulResponse < Net::HTTPSuccess
    def initialize(body)
      @body = body
    end

    attr_reader :body
  end

  class StubHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout, :ipaddr
    attr_reader :last_request

    def initialize(response)
      @response = response
    end

    def start
      yield self
    end

    def request(request)
      @last_request = request
      @response
    end
  end

  FakeAddressInfo = Struct.new(:ip_address)

  test "returns the forecast for the ZIP code" do
    zip_response = SuccessfulResponse.new(
      '{"places":[{"latitude":"38.8951","longitude":"-77.0364","place name":"Washington","state":"District of Columbia"}]}'
    )
    weather_response = SuccessfulResponse.new(
      '{"current":{"temperature_2m":72.5},"daily":{"temperature_2m_max":[76.1],"temperature_2m_min":[61.3]}}'
    )

    with_mocked_http(zip_response, weather_response) do |http_clients, dns_queries|
      result = WeatherForecastService.new("20500").call

      assert_equal(
        {
          zip_code: "20500",
          city: "Washington",
          state: "District of Columbia",
          temperature: 72.5,
          high: 76.1,
          low: 61.3,
          unit: "°F"
        },
        result
      )

      assert_equal 2, http_clients.length
      assert_equal "/us/20500", http_clients.first.last_request.path
      assert_equal "WeatherForecastRails/1.0", http_clients.first.last_request["User-Agent"]

      weather_query = URI.decode_www_form(
        URI("https://example.test#{http_clients.last.last_request.path}").query
      ).to_h
      assert_equal "38.8951", weather_query["latitude"]
      assert_equal "-77.0364", weather_query["longitude"]
      assert_equal "fahrenheit", weather_query["temperature_unit"]
      assert_equal 2, dns_queries.length
      assert_equal [ "api.zippopotam.us", "api.open-meteo.com" ], dns_queries.map(&:first)
    end
  end

  test "raises ForecastError when the ZIP code has no location" do
    response = SuccessfulResponse.new('{"places":[]}')

    with_mocked_http(response) do
      error = assert_raises(WeatherForecastService::ForecastError) do
        WeatherForecastService.new("00000").call
      end

      assert_equal "ZIP Code not found.", error.message
    end
  end

  test "raises ForecastError when the ZIP API returns an unsuccessful response" do
    with_mocked_http(Net::HTTPNotFound.new("1.1", "404", "Not Found")) do
      error = assert_raises(WeatherForecastService::ForecastError) do
        WeatherForecastService.new("20500").call
      end

      assert_equal "External service returned HTTP 404.", error.message
    end
  end

  test "raises ForecastError when the weather API returns an unsuccessful response" do
    zip_response = SuccessfulResponse.new(
      '{"places":[{"latitude":"38.8951","longitude":"-77.0364","place name":"Washington","state":"District of Columbia"}]}'
    )

    with_mocked_http(zip_response, Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable")) do
      error = assert_raises(WeatherForecastService::ForecastError) do
        WeatherForecastService.new("20500").call
      end

      assert_equal "External service returned HTTP 503.", error.message
    end
  end

  test "raises ForecastError when forecast data is incomplete" do
    zip_response = SuccessfulResponse.new(
      '{"places":[{"latitude":"38.8951","longitude":"-77.0364","place name":"Washington","state":"District of Columbia"}]}'
    )
    weather_response = SuccessfulResponse.new(
      '{"current":{"temperature_2m":72.5},"daily":{"temperature_2m_max":[76.1]}}'
    )

    with_mocked_http(zip_response, weather_response) do
      error = assert_raises(WeatherForecastService::ForecastError) do
        WeatherForecastService.new("20500").call
      end

      assert_equal "Incomplete weather forecast data.", error.message
    end
  end

  test "translates malformed JSON into a weather service error" do
    with_mocked_http(SuccessfulResponse.new("{")) do
      error = assert_raises(WeatherForecastService::ForecastError) do
        WeatherForecastService.new("20500").call
      end

      assert_match(/\AWeather service unavailable:/, error.message)
    end
  end

  test "translates network errors into a weather service error" do
    dns_failure = ->(*) { raise SocketError, "DNS lookup failed" }

    with_stubbed_method(Addrinfo, :getaddrinfo, dns_failure) do
      error = assert_raises(WeatherForecastService::ForecastError) do
        WeatherForecastService.new("20500").call
      end

      assert_equal "Weather service unavailable: DNS lookup failed", error.message
    end
  end

  private

  def with_mocked_http(*responses)
    http_clients = []
    dns_queries = []
    response_queue = responses.dup
    dns_lookup = ->(*args) do
      dns_queries << args
      [ FakeAddressInfo.new("192.0.2.1") ]
    end
    http_factory = ->(*) do
      http = StubHttp.new(response_queue.shift)
      http_clients << http
      http
    end

    with_stubbed_method(Addrinfo, :getaddrinfo, dns_lookup) do
      with_stubbed_method(Net::HTTP, :new, http_factory) do
        yield http_clients, dns_queries
      end
    end
  end

  def with_stubbed_method(target, method_name, replacement)
    original = target.method(method_name)
    target.define_singleton_method(method_name, replacement)
    yield
  ensure
    target.define_singleton_method(method_name, original)
  end
end
