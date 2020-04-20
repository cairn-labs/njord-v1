defmodule TraderWeb.ApiUtil do
  @doc """
  Returns a successful JSON response.
  """
  def send_success(conn, data \\ %{}) do
    Phoenix.Controller.json(conn, data)
  end

  @doc """
  Return a JSON error response containing a HTTP status code and optional message.
  """
  def send_error(%{resp_headers: resp_headers} = conn, http_status_code, message \\ nil) do
    data =
      if message do
        %{message: message}
      else
        %{}
      end

    %{conn | resp_headers: [{"content-type", "application/json; charset=utf-8"} | resp_headers]}
    |> Plug.Conn.send_resp(http_status_code, Jason.encode!(data))
  end
end
