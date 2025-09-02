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
      <div class="space-y-8">
        <!-- Header -->
        <div class="text-center">
          <h1 class="text-4xl font-bold text-primary mb-2">VM Monitor Dashboard</h1>
          <p class="text-base-content/70">Real-time system monitoring and VM control</p>
        </div>

        <!-- Memory Stats -->
        <div class="stats shadow w-full">
          <div class="stat">
            <div class="stat-figure text-primary">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
            </div>
            <div class="stat-title">Total Memory</div>
            <div class="stat-value text-primary">{Sizeable.filesize(@memory.total)}</div>
          </div>

          <div class="stat">
            <div class="stat-figure text-secondary">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4"></path>
              </svg>
            </div>
            <div class="stat-title">Used Memory</div>
            <div class="stat-value text-secondary">{Sizeable.filesize(@memory.used)}</div>
          </div>

          <div class="stat">
            <div class="stat-figure text-accent">
              <div class="radial-progress text-accent" style={"--value:#{round(@memory.used / max(@memory.total,1) * 100)}; --size:3rem;"}>
                {round(@memory.used / max(@memory.total,1) * 100)}%
              </div>
            </div>
            <div class="stat-title">Usage Percentage</div>
            <div class="stat-value text-accent">{round(@memory.used / max(@memory.total,1) * 100)}%</div>
            <div class="stat-desc">Current memory utilization</div>
          </div>
        </div>

        <!-- VM Control Panel -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title text-2xl mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 17.25v-.228a4.5 4.5 0 00-.12-1.03l-2.268-9.64a3.375 3.375 0 00-3.285-2.602H7.923a3.375 3.375 0 00-3.285 2.602l-2.268 9.64a4.5 4.5 0 00-.12 1.03v.228m19.5 0a3 3 0 01-3 3H5.25a3 3 0 01-3-3m19.5 0a3 3 0 00-3-3H5.25a3 3 0 00-3 3m16.5 0h.008v.008h-.008V21m-3.75 0h.008v.008h-.008V21m-3.75 0h.008v.008h-.008V21m-3.75 0h.008v.008h-.008V21" />
              </svg>
              VM Control Panel
            </h2>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <!-- Add VMs Section -->
              <div class="space-y-4">
                <h3 class="text-lg font-semibold text-success">Add VMs</h3>
                <div class="flex flex-wrap gap-2">
                  <button class="btn btn-success btn-sm" phx-click="add" phx-value-count="1">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                    </svg>
                    1
                  </button>
                  <button class="btn btn-success btn-sm" phx-click="add" phx-value-count="10">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                    </svg>
                    10
                  </button>
                  <button class="btn btn-success btn-sm" phx-click="add" phx-value-count="100">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                    </svg>
                    100
                  </button>
                </div>
              </div>

              <!-- Remove VMs Section -->
              <div class="space-y-4">
                <h3 class="text-lg font-semibold text-error">Remove VMs</h3>
                <div class="flex flex-wrap gap-2">
                  <button class="btn btn-error btn-sm" phx-click="remove" phx-value-count="1">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15" />
                    </svg>
                    1
                  </button>
                  <button class="btn btn-error btn-sm" phx-click="remove" phx-value-count="10">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15" />
                    </svg>
                    10
                  </button>
                  <button class="btn btn-error btn-sm" phx-click="remove" phx-value-count="100">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15" />
                    </svg>
                    100
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- VM Status Details -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title text-2xl mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 3v11.25A2.25 2.25 0 006 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0118 16.5h-2.25m-7.5 0h7.5m-7.5 0l-1 3m8.5-3l1 3m0 0l-1-3m1 3l-1-3m-16.5-3h9.75" />
              </svg>
              System Status Details
            </h2>
            <div class="mockup-code">
              <pre class="text-sm"><code>{inspect(@status, pretty: true)}</code></pre>
            </div>
          </div>
        </div>

        <!-- Memory Details -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title text-2xl mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-8">
                <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 3v1.125C8.25 5.004 9.004 5.75 9.75 5.75h4.5c.746 0 1.5-.746 1.5-1.625V3M8.25 3V2.25C8.25 1.004 9.004.25 9.75.25h4.5c.746 0 1.5.746 1.5 1.5V3m-7.5 0h7.5m-7.5 10.703v2.047c0 .746.746 1.5 1.5 1.5h6c.746 0 1.5-.754 1.5-1.5v-2.047M8.25 13.703V12c0-.746.746-1.5 1.5-1.5h4.5c.746 0 1.5.754 1.5 1.5v1.703" />
              </svg>
              Memory Details
            </h2>
            <div class="mockup-code">
              <pre class="text-sm"><code>{inspect(@memory, pretty: true)}</code></pre>
            </div>
          </div>
        </div>
      </div>
    """
  end
end
