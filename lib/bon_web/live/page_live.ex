defmodule BonWeb.Live.PageLive do
  use BonWeb, :live_view

  def mount(_params, _session, socket) do
    Application.ensure_all_started(:memsup)
    status = Bon.VMSupervisor.status()
    Phoenix.PubSub.subscribe(Bon.PubSub, "status")
    t = System.monotonic_time(:millisecond)
    tick(0)

    socket =
      socket
      |> assign(status: status, refresh: nil, dirty?: false, memory: %{total: 0, used: 0})

    {:ok, socket}
  end

  defp tick(t \\ 1) do
    Process.send_after(self(), :tick, t * 1000)
  end

  def handle_info(:tick, socket) do
    IO.puts("Tick")
    sysmem = :memsup.get_system_memory_data()
    total = Keyword.get(sysmem, :system_total_memory)
    used = Keyword.get(sysmem, :buffered_memory) + Keyword.get(sysmem, :cached_memory)
    tick()
    {:noreply, assign(socket, memory: %{total: total, used: used})}
  end

  def handle_info(:change, %{assigns: %{refresh: nil}} = socket) do
    t =
      Task.async(fn ->
        Bon.VMSupervisor.status()
      end)

    {:noreply, assign(socket, refresh: t, dirty?: false)}
  end

  def handle_info(:change, socket) do
    {:noreply, assign(socket, dirty?: true)}
  end

  def handle_info({_ref, result}, socket) do
    if socket.assigns.dirty? do
      t =
        Task.async(fn ->
          Bon.VMSupervisor.status()
        end)

      {:noreply, assign(socket, status: result, refresh: t, dirty?: false)}
    else
      {:noreply, assign(socket, status: result, refresh: nil, dirty?: false)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  def handle_event("add", %{"count" => count}, socket) do
    count = String.to_integer(count)
    IO.inspect(count)
    Bon.VMSupervisor.add(count)
    {:noreply, socket}
  end

  def handle_event("remove", %{"count" => count}, socket) do
    count = String.to_integer(count)
    Bon.VMSupervisor.remove(count)
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <pre>
    {inspect(@status, pretty: true)}
    {inspect(@memory, pretty: true)}
    </pre>
    <h2>Memory Usage</h2>
    <div>Total: {Sizeable.filesize(@memory.total)}</div>
    <div>Used: {Sizeable.filesize(@memory.used)}</div>
    <div>Percentage: {round(@memory.used / max(@memory.total,1)) * 100}%</div>
    <button class="btn" phx-click="add" phx-value-count="1">+1</button>
    <button class="btn" phx-click="add" phx-value-count="10">+10</button>
    <button class="btn" phx-click="add" phx-value-count="100">+100</button>
    <button class="btn" phx-click="remove" phx-value-count="1">-1</button>
    <button class="btn" phx-click="remove" phx-value-count="10">-10</button>
    <button class="btn" phx-click="remove" phx-value-count="100">-100</button>
    """
  end
end
