defmodule Trader.Reddit.RedditDataCollector do
  require Logger
  use GenServer
  alias Trader.Db

  @login_base_url "https://www.reddit.com"
  @api_base_url "https://oauth.reddit.com"
  @subreddits [
    "wallstreetbets",
    "investing",
    "bitcoin",
    "btc",
    "ethtrader",
    "news",
    "cryptocurrency"
  ]
  @user_agent "TendiesAi/0.1 by samelaaaa"

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
      Logger.debug("Starting Reddit DataCollector GenServer...")
      token = get_new_token()
      Process.send_after(self(), :tick, 1000)
      {:ok, %{token: token}}
    else
      {:ok, %{token: nil}}
    end
  end

  @impl true
  def handle_info(:tick, %{token: token} = state) do
    for subreddit <- @subreddits do
      retrieve_top_links(subreddit, token)
    end

    queue_next_tick(self())
    {:noreply, state}
  end

  defp get_new_token() do
    config = Application.get_env(:trader, __MODULE__)

    auth = [hackney: [basic_auth: {config[:api_id], config[:api_secret]}]]

    headers = [
      {"User-Agent", @user_agent},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    payload =
      "grant_type=password&username=#{config[:api_user]}&password=#{config[:api_password]}"

    {:ok, %HTTPoison.Response{body: response}} =
      HTTPoison.post(
        @login_base_url <> "/api/v1/access_token",
        payload,
        headers,
        auth
      )

    response
    |> Jason.decode!()
    |> Map.get("access_token")
  end

  defp retrieve_top_links(subreddit, token) do
    headers = [
      {"User-Agent", @user_agent},
      {"Authorization", "bearer #{token}"}
    ]

    {:ok, %HTTPoison.Response{body: response}} =
      HTTPoison.get(
        @api_base_url <> "/r/#{subreddit}/hot",
        headers
      )

    %{"data" => %{"children" => posts}} =
      response
      |> Jason.decode!()

    posts
    |> Enum.flat_map(&post_to_proto/1)
    |> create_datapoint(subreddit)
    |> Db.DataPoints.insert_datapoint()
  end

  defp post_to_proto(%{
         "title" => title,
         "selftext" => text,
         "permalink" => permalink,
         "url" => url,
         "ups" => upvotes,
         "upvote_ratio" => upvote_ratio,
         "created_utc" => created_utc
       }) do
    [
      RedditPost.new(
        title: title,
        permalink: permalink,
        text: text,
        url: url,
        upvotes: upvotes,
        upvote_ratio: upvote_ratio,
        created_utc: created_utc
      )
    ]
  end

  defp post_to_proto(_) do
    []
  end

  defp create_datapoint(posts, subreddit_name) do
    DataPoint.new(
      event_timestamp: DateTime.utc_now() |> DateTime.to_unix(:microsecond),
      data_point_type: :SUBREDDIT_TOP_LISTING,
      subreddit_top_listing:
        SubredditTopListing.new(
          subreddit_name: subreddit_name,
          posts: posts
        )
    )
  end

  defp queue_next_tick(pid) do
    calls_per_minute = Application.get_env(:trader, __MODULE__)[:max_calls_per_minute]
    delay = round(60_000 / (calls_per_minute / length(@subreddits)))
    spawn(fn -> Process.send_after(pid, :tick, delay) end)
  end
end
