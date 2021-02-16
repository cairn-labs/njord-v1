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
  @links_per_call 25
  @min_timeout_between_calls_ms 4_000

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
      get_with_retry(
        @api_base_url <> "/r/#{subreddit}/hot?limit=#{@links_per_call}",
        headers
      )

    %{"data" => %{"children" => posts}} =
      response
      |> Jason.decode!()

    posts
    |> Enum.flat_map(&post_to_proto/1)
    |> Enum.map(fn post -> add_comments(post, subreddit, token) end)
    |> create_datapoint(subreddit)
    |> Db.DataPoints.insert_datapoint()
  end

  defp post_to_proto(%{"data" => %{
         "title" => title,
         "selftext" => text,
         "author" => author,
         "permalink" => permalink,
         "url" => url,
         "ups" => upvotes,
         "upvote_ratio" => upvote_ratio,
         "created_utc" => created_utc,
         "id" => id
       } = data}) do
    [
      RedditPost.new(
        title: title,
        permalink: permalink,
        text: text,
        url: url,
        author: author,
        upvotes: upvotes,
        upvote_ratio: upvote_ratio,
        created_utc: round(created_utc),
        id: id
      )
    ]
  end

  defp post_to_proto(x) do
    Logger.warn("Reddit post in incorrect format; skipping...")
    []
  end

  defp comment_to_proto(%{
        "id" => id,
        "ups" => ups,
        "downs" => downs,
        "created_utc" => created_utc,
        "author" => username,
        "body" => content,
        "parent_id" => parent_id
                        }) do
    [RedditComment.new(
        id: id,
        username: username,
        content: content,
        created_utc: round(created_utc),
        parent_id: parent_id,
        upvotes: ups,
        downvotes: downs
    )]
  end

  defp comment_to_proto(_) do
    Logger.warn("Reddit comment in incorrect format; skipping...")
    []
  end

  defp add_comments(%RedditPost{id: id} = post, subreddit, token) do
    :timer.sleep(@min_timeout_between_calls_ms)

    headers = [
      {"User-Agent", @user_agent},
      {"Authorization", "bearer #{token}"}
    ]

    {:ok, %HTTPoison.Response{body: response}} =
      get_with_retry(
        @api_base_url <> "/r/#{subreddit}/comments?article=t3_#{id}&depth=2&limit=50",
        headers
      )

    comments =
      response
      |> Jason.decode!
      |> Map.get("data", %{})
      |> Map.get("children", [])
      |> Enum.flat_map(fn %{"data" => data} -> comment_to_proto(data) end)

    %RedditPost{post | comments: comments}
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
    delay = min(
      round(60_000 / (calls_per_minute / (@links_per_call * length(@subreddits)))),
      @min_timeout_between_calls_ms * @links_per_call * (length(@subreddits) + 1)
      )

    Logger.info("Delay is #{delay}")
    # spawn(fn -> Process.send_after(pid, :tick, delay) end)
  end

  def get_with_retry(url, headers) do
    get_with_retry(url, headers, 0)
  end

  def get_with_retry(url, headers, delay_ms) do
    :timer.sleep(delay_ms)
    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{} = response} -> {:ok, response}
      _ ->
        Logger.warn("Reddit API call failed, retrying in #{delay_ms + 10_000} ms")
        get_with_retry(url, headers, delay_ms + 10_000)
    end
  end
end
