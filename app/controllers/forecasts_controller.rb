class ForecastsController < ApplicationController
  def index
    @address = params[:address].to_s.strip
    return if @address.empty?

    @zip_code = ZipCodeResolver.new(@address).call
  rescue ZipCodeResolver::AddressNotFound => e
    @error = e.message
  end
end
