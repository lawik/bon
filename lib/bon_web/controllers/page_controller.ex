defmodule BonWeb.PageController do
  use BonWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
