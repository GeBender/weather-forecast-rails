require "test_helper"
require "net/http"
require "socket"

class ZipCodeResolverTest < ActiveSupport::TestCase
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

  test "returns the ZIP code directly when the address already contains one" do
    no_dns_lookup = ->(*) { raise "DNS should not be used for an address with a ZIP code" }

    with_stubbed_method(Addrinfo, :getaddrinfo, no_dns_lookup) do
      assert_equal "80202", ZipCodeResolver.new("Denver, CO 80202-1234").call
    end
  end

  test "looks up the ZIP code when the address does not contain one" do
    response = SuccessfulResponse.new(
      '[{"address":{"postcode":"10001-1234"}}]'
    )

    with_mocked_http(response) do |http|
      result = ZipCodeResolver.new("New York, NY").call

      assert_equal "10001", result
      assert_equal "WeatherForecastRails/1.0 (personal assessment project)", http.last_request["User-Agent"]

      query = URI.decode_www_form(URI("https://example.test#{http.last_request.path}").query).to_h
      assert_equal "New York, NY", query["q"]
      assert_equal "jsonv2", query["format"]
    end
  end

  test "raises AddressNotFound when geocoding returns no ZIP code" do
    response = SuccessfulResponse.new('[{"address":{"city":"New York"}}]')

    with_mocked_http(response) do
      error = assert_raises(ZipCodeResolver::AddressNotFound) do
        ZipCodeResolver.new("New York, NY").call
      end

      assert_equal "No valid US ZIP Code found for this address.", error.message
    end
  end

  test "raises AddressNotFound when the geocoding service returns an unsuccessful response" do
    with_mocked_http(Net::HTTPNotFound.new("1.1", "404", "Not Found")) do
      error = assert_raises(ZipCodeResolver::AddressNotFound) do
        ZipCodeResolver.new("New York, NY").call
      end

      assert_equal "Unable to look up this address.", error.message
    end
  end

  test "raises AddressNotFound for a blank address" do
    error = assert_raises(ZipCodeResolver::AddressNotFound) do
      ZipCodeResolver.new("  ").call
    end

    assert_equal "Please enter an address.", error.message
  end

  test "translates malformed JSON into a temporary service error" do
    response = SuccessfulResponse.new("{")

    with_mocked_http(response) do
      error = assert_raises(ZipCodeResolver::AddressNotFound) do
        ZipCodeResolver.new("New York, NY").call
      end

      assert_equal "Address lookup service is temporarily unavailable.", error.message
    end
  end

  test "translates network errors into a temporary service error" do
    with_stubbed_method(Addrinfo, :getaddrinfo, ->(*) { raise SocketError, "DNS lookup failed" }) do
      error = assert_raises(ZipCodeResolver::AddressNotFound) do
        ZipCodeResolver.new("New York, NY").call
      end

      assert_equal "Address lookup service is temporarily unavailable.", error.message
    end
  end

  private

  def with_mocked_http(response)
    http = StubHttp.new(response)

    with_stubbed_method(Addrinfo, :getaddrinfo, ->(*) { [ FakeAddressInfo.new("192.0.2.1") ] }) do
      with_stubbed_method(Net::HTTP, :new, ->(*) { http }) do
        yield http
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
