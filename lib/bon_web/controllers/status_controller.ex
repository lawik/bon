defmodule BonWeb.Controllers.StatusController do
  use BonWeb, :controller

  def report(conn, %{"identifier" => identifier}) do
    Bon.VM.report(identifier)
    send_resp(conn, 200, "Report received")
  end
end
