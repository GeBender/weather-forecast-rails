# Weather Forecast

A small Rails app for checking the weather at a US address. Enter an address and the app finds its ZIP Code, then shows the current temperature and today's high and low in Fahrenheit.

## Run it locally

You'll need Ruby 3.3.8, Bundler, and SQLite.

```bash
bundle install
bin/rails db:prepare
bin/rails server
```

Open [http://localhost:3000](http://localhost:3000) and try an address, such as:

```text
1600 Pennsylvania Avenue NW, Washington, DC
```

The app needs an internet connection when it has to look up an address or fetch a new forecast.

## Where the data comes from

- [Nominatim](https://nominatim.org/) looks up addresses that don't already include a ZIP Code. It uses [OpenStreetMap data](https://www.openstreetmap.org/copyright).
- [Zippopotam.us](https://www.zippopotam.us/) provides the location for a ZIP Code.
- [Open-Meteo](https://open-meteo.com/) provides current conditions and the day's high and low.

## Caching

Forecasts are cached by ZIP Code for 15 minutes, so another lookup in the same area can reuse the result. In development, Rails uses an in-memory cache, which is cleared when the app restarts.

## Tests

```bash
bin/rails test
bin/rubocop
bin/brakeman
```

The service tests stub the external APIs, so they don't depend on those services being online.