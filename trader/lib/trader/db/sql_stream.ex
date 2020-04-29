defmodule Trader.Db.SqlStream do
  alias Trader.Repo
  alias Ecto.Adapters.SQL

  @doc """
  Takes a SQL query as a string, and its params (except LIMIT and OFFSET)
  as a list. Assumes that the last two placeholders in the query string
  correspond to LIMIT and OFFSET. Returns a Stream that continuously generates
  new values, paging using LIMIT and OFFSET.
  """
  def stream(query, params, opts \\ []) do
    chunksize = Keyword.get(opts, :chunksize, 50)

    Stream.resource(
      fn -> {query, params, chunksize, 0} end,
      &get_more_content/1,
      fn _ -> :ok end
    )
  end

  defp get_page(query, params) do
    {:ok, %{rows: rows}} = SQL.query(Repo, query, params)
    rows
  end

  def get_more_content({query, params, limit, offset} = acc) do
    case get_page(query, params ++ [limit, offset + limit]) do
      [] ->
        {:halt, acc}

      next_page ->
        {next_page, {query, params, limit, offset + limit}}
    end
  end
end
