defmodule Trader.Newsapi.NewsapiDataCollector do
  require Logger
  use GenServer
  alias Trader.Db

  @api_base_url "http://newsapi.org/v2/"
  @searches [
    {:top_headlines, "us"},
    {:query, "bitcoin"}
  ]

  ##########
  # Client #
  ##########

  def start_link([]) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  ##########
  # Server #
  ##########

  @impl true
  def init(_state) do
    if Keyword.get(Application.get_env(:trader, __MODULE__), :enable, true) do
      Logger.debug("Starting NewsApi DataCollector GenServer...")
      Process.send_after(self(), :tick, 500)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    for search <- @searches do
      case search do
        {:top_headlines, country} -> retrieve_top_headlines(country)
        {:query, query} -> retrieve_search_results(query)
      end
    end

    queue_next_tick(self())
    {:noreply, state}
  end

  defp retrieve_top_headlines(country_code) do
    api_key = Application.get_env(:trader, __MODULE__)[:api_key]

    {:ok, %HTTPoison.Response{body: response}} =
      HTTPoison.get(
        @api_base_url <> "/top-headlines",
        [],
        params: %{"country" => country_code, "apiKey" => api_key}
      )

    response
    |> Jason.decode!()
    |> Map.get("articles", [])
    |> Enum.flat_map(fn d -> headline_article_to_proto(d, country_code) end)
    |> Enum.each(&Db.DataPoints.insert_datapoint_if_not_exists/1)
  end

  def headline_article_to_proto(article_json, country_code) do
    {:ok, published_at, 0} =
      article_json
      |> Map.get("publishedAt")
      |> DateTime.from_iso8601()

    case article_json_to_proto(article_json) do
      {:ok, item} ->
        proto =
          DataPoint.new(
            event_timestamp: published_at |> DateTime.to_unix(:microsecond),
            data_point_type: :NEWS_API_ITEM,
            news_api_item: %NewsApiItem{item | country: country_code, search_type: :TOP_HEADLINES}
          )

        [proto]

      :error ->
        Logger.warn("Badly formatted News API item found; skipping.")
        []
    end
  end

  def search_article_to_proto(article_json, query) do
    {:ok, published_at, 0} =
      article_json
      |> Map.get("publishedAt")
      |> DateTime.from_iso8601()

    case article_json_to_proto(article_json) do
      {:ok, item} ->
        proto =
          DataPoint.new(
            event_timestamp: published_at |> DateTime.to_unix(:microsecond),
            data_point_type: :NEWS_API_ITEM,
            news_api_item: %NewsApiItem{item | query: query, search_type: :QUERY}
          )

        [proto]

      :error ->
        Logger.warn("Badly formatted News API item found; skipping.")
        []
    end
  end

  defp article_json_to_proto(%{
         "source" => %{"name" => source},
         "title" => title,
         "description" => description,
         "url" => url,
         "content" => content
       }) do
    {:ok,
     NewsApiItem.new(
       source: source,
       title: title,
       description: description,
       url: url,
       content: content
     )}
  end

  defp article_json_to_proto(_) do
    :error
  end

  defp retrieve_search_results(query) do
    api_key = Application.get_env(:trader, __MODULE__)[:api_key]
    calls_per_day = Application.get_env(:trader, __MODULE__)[:max_calls_per_day]
    window_length_ms = round(86_400_000 / (calls_per_day / length(@searches))) * 10
    to = DateTime.utc_now() |> DateTime.to_iso8601()

    from =
      DateTime.utc_now()
      |> DateTime.add(-window_length_ms, :millisecond)
      |> DateTime.to_iso8601()

    {:ok, %HTTPoison.Response{body: response}} =
      HTTPoison.get(
        @api_base_url <> "/everything",
        [],
        params: %{"q" => query, "apiKey" => api_key, "from" => from, "to" => to}
      )

    response
    |> Jason.decode!()
    |> Map.get("articles", [])
    |> Enum.flat_map(fn d -> search_article_to_proto(d, query) end)
    |> Enum.each(&Db.DataPoints.insert_datapoint_if_not_exists/1)
  end

  defp queue_next_tick(pid) do
    calls_per_day = Application.get_env(:trader, __MODULE__)[:max_calls_per_day]
    delay = round(86_400_000 / (calls_per_day / length(@searches)))
    spawn(fn -> Process.send_after(pid, :tick, delay) end)
  end
end
