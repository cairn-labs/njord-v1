defmodule TraderWeb.IndexController do
  use TraderWeb, :controller
  alias TraderWeb.ApiUtil
  require Logger

  def index(conn, _params) do
    ApiUtil.send_success(conn, %{"status" => "OK"})
  end
end
