require "net/http"
require "json"
require "socket"

class ZipCodeResolver
  class AddressNotFound < StandardError; end

  API_URL = "https://nominatim.openstreetmap.org/search"

  def initialize(address)
    @address = address.to_s.strip
  end

  def call
    raise AddressNotFound, "Please enter an address." if @address.empty?

    zip_code_from_address || zip_code_from_geocoding
  end

  private

  # Extracts the ZIP code directly from the address string if present.
  def zip_code_from_address
    @address.match(/\b\d{5}(?:-\d{4})?\b/)&.to_s&.slice(0, 5)
  end

  # Uses the OpenStreetMap Nominatim API to geocode the address and extract the ZIP code.
  def zip_code_from_geocoding
    uri = URI(API_URL)
    uri.query = URI.encode_www_form(
      q: @address,
      format: "jsonv2",
      addressdetails: 1,
      countrycodes: "us",
      limit: 1
    )

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "WeatherForecastRails/1.0 (personal assessment project)"

    # Resolve the IPv4 address of the host to ensure the request uses IPv4.
    ipv4 = Addrinfo.getaddrinfo(
        uri.host,
        uri.port,
        Socket::AF_INET,
        Socket::SOCK_STREAM
    ).first.ip_address

    # Use the resolved IPv4 address for the HTTP connection.
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10
    http.ipaddr = ipv4

    response = http.start do |connection|
        connection.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise AddressNotFound, "Unable to look up this address."
    end

    # Parse the JSON response and extract the location information.
    location = JSON.parse(response.body).first
    zip_code = location&.dig("address", "postcode")

    unless zip_code&.match?(/\A\d{5}(?:-\d{4})?\z/)
      raise AddressNotFound, "No valid US ZIP Code found for this address."
    end

    # Return the first 5 digits of the ZIP code.
    zip_code[0, 5]
  rescue JSON::ParserError, IOError, SocketError, SystemCallError, Timeout::Error
    raise AddressNotFound, "Address lookup service is temporarily unavailable."
  end
end
