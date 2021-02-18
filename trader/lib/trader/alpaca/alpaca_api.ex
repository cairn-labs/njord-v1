defmodule Trader.Alpaca.AlpacaApi do
  require Logger

  def call(api, method, endpoint) do
    call(api, method, endpoint, "")
  end

  def call(api, method, endpoint, body) do
    config = Application.get_env(:trader, __MODULE__)
    api_key = config[:api_key]
    api_secret = config[:api_secret]

    method_str =
      case method do
        :POST -> "POST"
        :GET -> "GET"
        :PUT -> "PUT"
      end

    body_str =
      case method do
        :GET -> ""
        _ -> Jason.encode!(body)
      end

    url =
      case api do
        :trading -> URI.merge(config[:trading_api_url], endpoint)
        :data -> URI.merge(config[:data_api_url], endpoint)
      end

    headers = [
      {"APCA-API-KEY-ID", api_key},
      {"APCA-API-SECRET-KEY", api_secret},
      {"Content-Type", "application/json"}
    ]

    case method do
      :GET -> HTTPoison.get(url, headers)
      :POST -> HTTPoison.post(url, body_str, headers)
      :PUT -> HTTPoison.put(url, body_str, headers)
    end
  end

  def parse_response({:ok, %HTTPoison.Response{body: body, status_code: 200}}) do
    Jason.decode!(body)
  end

  def parse_response(response) do
    Logger.error("Invalid response from Alpaca: #{inspect(response)}")
    :error
  end
end
