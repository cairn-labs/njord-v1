defmodule Trader.Alpaca.AlpacaApi do
  require Logger

  @max_retries 5
  @initial_retry_pause_ms 2000

  def call(api, method, endpoint, opts \\ []) do
    call(api, method, endpoint, "", opts)
  end

  def call(api, method, endpoint, body, opts) do
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

    request =
      case method do
        :GET -> fn -> HTTPoison.get(url, headers) end
        :POST -> fn -> HTTPoison.post(url, body_str, headers) end
        :PUT -> fn -> HTTPoison.put(url, body_str, headers) end
      end

    if Keyword.get(opts, :retry, false) do
      retry_if_necessary(request, 0, @initial_retry_pause_ms)
    else
      {:ok, result} = request.()
      result
    end
  end

  defp retry_if_necessary(_, @max_retries, _) do
    {:error, :too_many_failures}
  end
  defp retry_if_necessary(request, past_retries, current_sleep) do
    case request.() do
      {:ok, result} -> result
      _ ->
        :timer.sleep(current_sleep)
        retry_if_necessary(request, past_retries + 1, current_sleep * 2)
    end
  end


  def parse_response(%HTTPoison.Response{body: body, status_code: 200}) do
    Jason.decode!(body)
  end

  def parse_response(response) do
    Logger.error("Invalid response from Alpaca: #{inspect(response)}")
    :error
  end
end
