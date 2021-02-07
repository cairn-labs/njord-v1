defmodule Trader.Polygon.PolygonApi do
  require Logger

  @max_retries 3
  @initial_retry_pause_ms 1000

  def call(method, endpoint) do
    call(method, endpoint, "")
  end

  defp call(method, endpoint, body, retry \\ true) do
    config = Application.get_env(:trader, __MODULE__)
    api_key = config[:api_key]
    api_url = config[:rest_api_url]

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

    headers = [
      {"Content-Type", "application/json"}
    ]

    url = URI.merge(config[:rest_api_url], add_url_param(endpoint, "apiKey", api_key))

    request =
      case method do
        :GET -> fn -> HTTPoison.get(url, headers) end
        :POST -> fn -> HTTPoison.post(url, body_str, headers) end
        :PUT -> fn -> HTTPoison.put(url, body_str, headers) end
      end

    if retry do
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

  defp add_url_param(endpoint, param_name, param_value) do
    delimiter = if String.contains?(endpoint, "?"), do: "&", else: "?"
    "#{endpoint}#{delimiter}#{param_name}=#{param_value}"
  end

  def paginate(method, endpoint, results_getter) do
    paginate(method, endpoint, "", results_getter)
  end

  def paginate(method, endpoint, body, results_getter) do
    Stream.iterate(1, fn x -> x + 1 end)
    |> Stream.map(fn i -> get_page(i, method, endpoint, body, results_getter) end)
    |> Stream.take_while(fn [] -> false; _ -> true end)
    |> Stream.flat_map(&(&1))
  end

  defp get_page(page_number, method, endpoint, body, results_getter) do
    Logger.debug("Getting page #{page_number}")
    case call(method, add_url_param(endpoint, "page", page_number)) do
      %HTTPoison.Response{status_code: 200, body: body} ->
        results_getter.(Jason.decode!(body))

      m ->
        Logger.error(inspect(m))
        []
    end
  end
end
