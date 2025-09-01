defmodule BonWeb.Live.PageLive do
  use BonWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~L"""
    <h1>Hello, World!</h1>
    """
  end
end
