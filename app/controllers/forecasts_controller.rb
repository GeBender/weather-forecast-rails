class ForecastsController < ApplicationController
  @cache_time = 15
  CACHE_DURATION = @cache_time.minutes

  def index
    @address = params[:address].to_s.strip
    return if @address.empty?

    @zip_code = ZipCodeResolver.new(@address).call

    cache_key = "forecast:#{@zip_code}"

    @forecast = Rails.cache.read(cache_key)
    @from_cache = @forecast.present?

    unless @from_cache
      @forecast = WeatherForecastService.new(@zip_code).call

      Rails.cache.write(
        cache_key,
        @forecast,
        expires_in: CACHE_DURATION
      )
    end

  rescue ZipCodeResolver::AddressNotFound,
         WeatherForecastService::ForecastError => e
    @error = e.message
  end
end
