defmodule BonWeb.Controllers.StatusController do
  use BonWeb, :controller
  require Logger

  def report(conn, %{"identifier" => mac}) do
    identifier = Bon.MacAddress.to_integer(mac)
    Logger.info("Received status: #{mac} -> #{identifier}")
    Bon.VM.report(identifier)
    send_resp(conn, 200, "Report received")
  end
end
