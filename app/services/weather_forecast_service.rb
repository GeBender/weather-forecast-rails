require "net/http"
require "json"
require "socket"
require "openssl"

class WeatherForecastService
  class ForecastError < StandardError; end

  ZIP_API = "https://api.zippopotam.us/us"
  WEATHER_API = "https://api.open-meteo.com/v1/forecast"

  def initialize(zip_code)
    @zip_code = zip_code.to_s
  end

  def call
    location = find_location
    fetch_forecast(location)
  end

  private

  # Find the location information for the given ZIP code using the ZIP API.
  def find_location
    uri = URI("#{ZIP_API}/#{@zip_code}")
    data = fetch_json(uri)

    place = data["places"]&.first

    raise ForecastError, "ZIP Code not found." unless place

    {
      latitude: place["latitude"],
      longitude: place["longitude"],
      city: place["place name"],
      state: place["state"]
    }
  end

  # Fetch the weather forecast for the given location using the weather API.
  def fetch_forecast(location)
    uri = URI(WEATHER_API)

    uri.query = URI.encode_www_form(
      latitude: location[:latitude],
      longitude: location[:longitude],
      current: "temperature_2m",
      daily: "temperature_2m_max,temperature_2m_min",
      temperature_unit: "fahrenheit",
      timezone: "auto",
      forecast_days: 1
    )

    data = fetch_json(uri)

    temperature = data.dig("current", "temperature_2m")
    high = data.dig("daily", "temperature_2m_max")&.first
    low = data.dig("daily", "temperature_2m_min")&.first

    if [ temperature, high, low ].any?(&:nil?)
      raise ForecastError, "Incomplete weather forecast data."
    end

    {
      zip_code: @zip_code,
      city: location[:city],
      state: location[:state],
      temperature: temperature,
      high: high,
      low: low,
      unit: "°F"
    }
  end

  def fetch_json(uri)
    ipv4 = Addrinfo.getaddrinfo(
      uri.host,
      uri.port,
      Socket::AF_INET,
      Socket::SOCK_STREAM
    ).first.ip_address

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10
    http.ipaddr = ipv4

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "WeatherForecastRails/1.0"

    response = http.start do |connection|
      connection.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise ForecastError, "External service returned HTTP #{response.code}."
    end

    JSON.parse(response.body)
  rescue JSON::ParserError, SocketError, SystemCallError,
         IOError, Timeout::Error, OpenSSL::SSL::SSLError => e
    raise ForecastError, "Weather service unavailable: #{e.message}"
  end
end
