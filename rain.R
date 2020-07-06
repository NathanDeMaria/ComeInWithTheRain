# Some docs: https://www.weather.gov/documentation/services-web-api
library(httr)
library(glue)
library(magrittr)
library(jsonlite)
library(lubridate)
library(RPushbullet)
library(purrr)
library(tibble)
library(dplyr)
library(stringr)


# Config ####
require_env <- function(name) {
  env_var <- Sys.getenv(name)
  if (env_var == "") {
    stop(glue("Must set {name} environment variable"))
  }
  env_var
}

# Some user agent string so NOAA knows who to yell at if you do something stupid
USER_AGENT <- require_env('USER_AGENT')
# Coordinates of the location to get
LATITUDE <- require_env('LATITUDE')
LONGITUDE <- require_env('LONGITUDE')
# RPushbullet creds
PUSH_API_KEY <- require_env('PUSH_API_KEY')
PUSH_DEVICE_ID <- require_env('PUSH_DEVICE_ID')


# NOAA utils ####
get_from_noaa <- function(...) {
  # Search "I’m getting a 403 (Forbidden/Access Denied) error from the API."
  # in https://weather-gov.github.io/api/general-faqs to see why
  GET(..., add_headers("User-Agent" = USER_AGENT)) %>% stop_for_status()
}

content_from_noaa <- function(...) {
  # NOAA returns "Content-Type: application/geo+json",
  # which httr::content can't parse by default
  content(..., as = 'text', encoding = 'UTF-8') %>% parse_json()
}

get_grid_url <- function(latitude, longitude) {
  # Get the grid request endpoint for a lat/long pair
  raw <- glue('https://api.weather.gov/points/{latitude},{longitude}') %>%
    get_from_noaa() %>%
    content_from_noaa()
  raw$properties$forecastGridData
}


nulls_to_nas <- function(x) x %>% map(~ifelse(is.null(.x), NA, .x))

# Next rain ####
# Known rainy ones:
# - Partly Cloudy then Slight Chance Showers And Thunderstorms
# - Chance Showers And Thunderstorms
# - Slight Chance Showers And Thunderstorms

# Not sure if this is everything yet...
is_rainy <- function(x) grepl('([Ss]hower|[Tt]hunderstorms)', x) 
# forecast$shortForecast %>% unique() %>% keep(is_rainy)

grid_url <- get_grid_url(LATITUDE, LONGITUDE)
forecast <- glue('{grid_url}/forecast') %>%
  get_from_noaa() %>%
  content_from_noaa() %>%
  .[['properties']] %>% .[['periods']] %>%
  map(nulls_to_nas) %>% map(as_tibble_row) %>% bind_rows()
forecast <- forecast %>% mutate(precipitation_chance = detailedForecast %>% str_match('[Cc]hance of precipitation is ([0-9]+)%') %>% .[,2] %>% as.numeric())
next_chance_of_rain <- forecast %>% filter(is_rainy(shortForecast) | !is.na(precipitation_chance)) %>%
  mutate(startTime = ymd_hms(startTime)) %>%
  arrange(startTime) %>%
  head(n = 1)


# Rain last week ####

#' Get nearby stations
#'
#' Get nearby stations from the url of a grid point
#' The top one might be the nearest?
#'
#' @param grid_url 
#'
#' @return tibble of stations
#' @export
#'
#' @examples
get_nearby_stations <- function(grid_url) {
  glue('{grid_url}/stations') %>%
    get_from_noaa() %>%
    content_from_noaa() %>%
    .[['features']] %>% 
    map(~.x[['properties']]) %>%
    map(unlist) %>% map(as_tibble_row) %>% bind_rows()
}


#' Get rain
#'
#' @param station_id 
#'
#' @return tibble containing the amount of rain (meters) over the last few days
#' @export
get_rain <- function(station_id) {
  # Get the amount of rain from the last few days
  observations <- glue('https://api.weather.gov/stations/{station_id}/observations') %>%
    get_from_noaa() %>% 
    content_from_noaa()
  
  units <- observations$features %>% map_chr(~.x$properties$precipitationLast6Hours$unitCode)
  if (!all(units == 'unit:m')) {
    stop("Units aren't all in meters")
  }
  
  rain_m <- observations %>% .[['features']] %>% map(~.x$properties$precipitationLastHour$value) %>% nulls_to_nas() %>% unlist()
  time <- observations$features %>% map(~.x$properties$timestamp) %>% map_dbl(ymd_hms) %>% as.POSIXct(origin = '1970-01-01', tz = 'UTC')
  tibble(rain_m, time) %>%
    # "proportion" is roughly "hours of time range this is responsible for
    mutate(proportion = as.numeric(lag(time) - time, units = 'hours')) %>% 
    # Scale the rain amount (probably down) to match the duration responsible for
    mutate(rain_m = rain_m * proportion) %>% 
    mutate(day = round_date(time, unit = 'day')) %>%
    group_by(day) %>%
    summarize(rain_m = sum(rain_m, na.rm = T))
}

# Assumes they're sorted so that the closest is first
station_id <- get_nearby_stations(grid_url)$stationIdentifier[1]
rain <- get_rain(station_id)
rain_in <- sum(rain$rain_m) * 39.3700787

message_body <- glue(
  "Rained {round(rain_in, 2)} inches this past week.\nNext rain: {pct}% on {name}.",
  pct = next_chance_of_rain$precipitation_chance,
  name = next_chance_of_rain$name
)

pbPost(
  "note", 
  title = 'Do you need to water?',
  body = message_body,
  apikey = PUSH_API_KEY,
  devices = PUSH_DEVICE_ID)
