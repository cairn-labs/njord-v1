defmodule Trader.Tradier.TradierApi do
  # Example call:
  # Trader.Tradier.TradierApi.call(:GET, "v1/markets/options/chains", params: [{"symbol", "AMD"}, {"expiration", "2021-12-31"}])
  def call(method, endpoint, options \\ []) do
    config = Application.get_env(:trader, __MODULE__)
    {api_token, api_url} =
      if Keyword.get(options, :force_live, false) do
        {config[:live_rest_api_token], config[:live_rest_api_url]}
      else
        {config[:rest_api_token], config[:rest_api_url]}
      end

    method_str =
      case method do
        :POST -> "POST"
        :GET -> "GET"
        :PUT -> "PUT"
      end

    body_str =
      case Keyword.get(options, :body) do
        nil -> []
        body -> Jason.encode!(body)
      end

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{api_token}"}
    ]

    params = Keyword.get(options, :params)

    url = URI.merge(api_url, endpoint)

    {:ok, response} =
      case method do
        :GET -> HTTPoison.get(url, headers, params: params)
        :POST -> HTTPoison.post(url, body_str, headers, params: params)
        :PUT -> HTTPoison.put(url, body_str, headers, params: params)
      end

    case response do
      %HTTPoison.Response{body: body} -> {:ok, Jason.decode!(body)}
      _ -> {:error, response}
    end
  end
end
