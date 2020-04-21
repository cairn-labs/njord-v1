defmodule Trader.Coinbase.CoinbaseApi do
  require Logger

  def call(method, endpoint) do
    call(method, endpoint, "")
  end

  defp call(method, endpoint, body) do
    config = Application.get_env(:trader, __MODULE__)
    api_key = config[:api_key]
    api_passphrase = config[:api_passphrase]
    api_secret = config[:api_secret]

    method_str =
      case method do
        :POST -> "POST"
        :GET -> "GET"
        :PUT -> "PUT"
      end

    timestamp_str = DateTime.utc_now() |> DateTime.to_unix() |> Integer.to_string()

    body_str =
      case method do
        :GET -> ""
        _ -> Jason.encode!(body)
      end

    prehash = timestamp_str <> method_str <> endpoint <> body_str
    key = Base.decode64!(api_secret)

    signature =
      :crypto.hmac(:sha256, key, prehash)
      |> Base.encode64()

    headers = [
      {"CB-ACCESS-KEY", api_key},
      {"CB-ACCESS-TIMESTAMP", timestamp_str},
      {"CB-ACCESS-PASSPHRASE", api_passphrase},
      {"CB-ACCESS-SIGN", signature},
      {"Content-Type", "application/json"}
    ]

    url = URI.merge(config[:rest_api_url], endpoint)

    case method do
      :GET -> HTTPoison.get(url, headers)
      :POST -> HTTPoison.post(url, body_str, headers)
      :PUT -> HTTPoison.put(url, body_str, headers)
    end
  end
end
