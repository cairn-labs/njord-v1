defmodule Mix.Tasks.Trader.Custom do
  require Logger
  alias Trader.Db

  @moduledoc """
  This is just a place to put custom code to run things as you're developing
  with full access to all the modules, protos etc.
  """

  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:trader)

    data =
      Db.DataPoints.get_data_before_time(DateTime.utc_now(), :STONK_AGGREGATE, "SPY-1")
      |> inspect
      |> Logger.info()
  end
end
