defmodule Trader.Polygon.PolygonApi do
  require Logger

  def call(method, endpoint) do
    call(method, endpoint, "")
  end

  defp call(method, endpoint, body) do
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

    case method do
      :GET -> HTTPoison.get!(url, headers)
      :POST -> HTTPoison.post!(url, body_str, headers)
      :PUT -> HTTPoison.put!(url, body_str, headers)
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
