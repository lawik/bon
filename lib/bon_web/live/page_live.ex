defmodule BonWeb.Live.PageLive do
  use BonWeb, :live_view

  def mount(_params, _session, socket) do
    Application.ensure_all_started(:memsup)
    Application.ensure_all_started(:cpu_sup)
    status = Bon.VMSupervisor.status()
    Phoenix.PubSub.subscribe(Bon.PubSub, "status")
    tick(0)

    socket =
      socket
      |> assign(
        status: status,
        refresh: nil,
        dirty?: false,
        memory: %{total: 0, used: 0},
        cpu: %{util: 0.0},
        form: to_form(%{"count" => to_string(status.running)})
      )

    {:ok, socket}
  end

  defp tick(t \\ 1) do
    Process.send_after(self(), :tick, t * 1000)
  end

  def handle_info(:tick, socket) do
    sysmem = :memsup.get_system_memory_data()
    Enum.each(sysmem, fn {k,v} ->
       IO.puts("#{k}: #{Sizeable.filesize(v)}")
    end)
    total = Keyword.get(sysmem, :system_total_memory, 0)
    used = total - Keyword.get(sysmem, :available_memory, 0)

    # Get CPU utilization
    cpu_util =
      case :cpu_sup.util() do
        {:badrpc, _} -> 0.0
        util when is_number(util) -> util
        _ -> 0.0
      end

    tick()
    {:noreply, assign(socket, memory: %{total: total, used: used}, cpu: %{util: cpu_util})}
  end

  def handle_info(:change, %{assigns: %{refresh: nil}} = socket) do
    IO.puts("refresh triggered")

    t =
      Task.async(fn ->
        Bon.VMSupervisor.status()
      end)

    {:noreply, assign(socket, refresh: t, dirty?: false)}
  end

  def handle_info(:change, socket) do
    IO.puts("dirty")
    {:noreply, assign(socket, dirty?: true)}
  end

  def handle_info({_ref, result}, socket) do
    IO.puts("received status update")
    current_count = result.running || 0

    updated_socket =
      assign(socket, status: result, form: to_form(%{"count" => to_string(current_count)}))

    if socket.assigns.dirty? do
      IO.puts("was dirty, refetching")

      t =
        Task.async(fn ->
          Bon.VMSupervisor.status()
        end)

      {:noreply, assign(updated_socket, refresh: t, dirty?: false)}
    else
      IO.puts("clean, not refetching")
      {:noreply, assign(updated_socket, refresh: nil, dirty?: false)}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  def handle_event("add", %{"count" => count}, socket) do
    count = String.to_integer(count)
    Bon.VMSupervisor.add(count)
    {:noreply, socket}
  end

  def handle_event("remove", %{"count" => count}, socket) do
    count = String.to_integer(count)
    Bon.VMSupervisor.remove(count)
    {:noreply, socket}
  end

  def handle_event("vm_count_form_change", %{"count" => count_str}, socket) do
    current_count = socket.assigns.status.running || 0

    case Integer.parse(count_str) do
      {target_count, ""} when target_count >= 0 ->
        cond do
          target_count > current_count ->
            Bon.VMSupervisor.add(target_count - current_count)

          target_count < current_count ->
            Bon.VMSupervisor.remove(current_count - target_count)

          true ->
            # target equals current, no action needed
            :ok
        end

        {:noreply, assign(socket, form: to_form(%{"count" => count_str}))}

      _ ->
        {:noreply, assign(socket, form: to_form(%{"count" => count_str}))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <!-- Header -->
      <div class="text-center">
        <h1 class="text-4xl font-bold text-primary mb-2">VM Monitor Dashboard</h1>
        <p class="text-base-content/70">Real-time system monitoring and VM control</p>
      </div>

      <div class="stats shadow w-full">
        <!-- CPU Stats -->
        <div class="stat">
          <div class="stat-figure text-warning">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="inline-block w-8 h-8 stroke-current"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
              />
            </svg>
          </div>
          <div class="stat-title">CPU Utilization</div>
          <div class="stat-value text-warning">
            {:erlang.float_to_binary(@cpu.util, decimals: 1)}%
          </div>
          <div class="stat-desc">Current CPU usage</div>
        </div>
        <!-- Memory Stats -->
        <div class="stat">
          <div class="stat-figure text-primary">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="inline-block w-8 h-8 stroke-current"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              >
              </path>
            </svg>
          </div>
          <div class="stat-title">Total Memory</div>
          <div class="stat-value text-primary">{Sizeable.filesize(@memory.total)}</div>
        </div>

        <div class="stat">
          <div class="stat-figure text-secondary">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="inline-block w-8 h-8 stroke-current"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4"
              >
              </path>
            </svg>
          </div>
          <div class="stat-title">Used Memory</div>
          <div class="stat-value text-secondary">{Sizeable.filesize(@memory.used)}</div>
        </div>

        <div class="stat">
          <div class="stat-figure text-accent">
            <div
              class="radial-progress text-accent"
              style={"--value:#{round(@memory.used / max(@memory.total,1) * 100)}; --size:3rem;"}
            >
              {round(@memory.used / max(@memory.total, 1) * 100)}%
            </div>
          </div>
          <div class="stat-title">Memory Usage</div>
          <div class="stat-value text-accent">
            {round(@memory.used / max(@memory.total, 1) * 100)}%
          </div>
          <div class="stat-desc">Current memory utilization</div>
        </div>
      </div>
      
    <!-- VM Control Panel -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-6 h-6"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M21.75 17.25v-.228a4.5 4.5 0 00-.12-1.03l-2.268-9.64a3.375 3.375 0 00-3.285-2.602H7.923a3.375 3.375 0 00-3.285 2.602l-2.268 9.64a4.5 4.5 0 00-.12 1.03v.228m19.5 0a3 3 0 01-3 3H5.25a3 3 0 01-3-3m19.5 0a3 3 0 00-3-3H5.25a3 3 0 00-3 3m16.5 0h.008v.008h-.008V21m-3.75 0h.008v.008h-.008V21m-3.75 0h.008v.008h-.008V21m-3.75 0h.008v.008h-.008V21"
              />
            </svg>
            VM Control Panel
          </h2>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <!-- Add VMs Section -->
            <div class="space-y-4">
              <h3 class="text-lg font-semibold text-success">Add VMs</h3>
              <div class="flex flex-wrap gap-2">
                <button class="btn btn-success btn-sm" phx-click="add" phx-value-count="1">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-4 h-4"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                  </svg>
                  1
                </button>
                <button class="btn btn-success btn-sm" phx-click="add" phx-value-count="10">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-4 h-4"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                  </svg>
                  10
                </button>
                <button class="btn btn-success btn-sm" phx-click="add" phx-value-count="100">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-4 h-4"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                  </svg>
                  100
                </button>
              </div>
            </div>
            
    <!-- Custom Count Form -->
            <div class="md:col-span-2 space-y-4">
              <h3 class="text-lg font-semibold text-info">Set VM Count</h3>
              <.form
                for={@form}
                phx-change="vm_count_form_change"
                phx-submit="vm_count_form_change"
                id="vm-count-form"
              >
                <.input
                  field={@form[:count]}
                  type="number"
                  label="Target VM Count"
                  class="input input-bordered input-info w-full"
                  phx-debounce="blur"
                  min="0"
                />
              </.form>
            </div>
            
    <!-- Remove VMs Section -->
            <div class="space-y-4">
              <h3 class="text-lg font-semibold text-error">Remove VMs</h3>
              <div class="flex flex-wrap gap-2">
                <button class="btn btn-error btn-sm" phx-click="remove" phx-value-count="1">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-4 h-4"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15" />
                  </svg>
                  1
                </button>
                <button class="btn btn-error btn-sm" phx-click="remove" phx-value-count="10">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-4 h-4"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15" />
                  </svg>
                  10
                </button>
                <button class="btn btn-error btn-sm" phx-click="remove" phx-value-count="100">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-4 h-4"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15" />
                  </svg>
                  100
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Run Count Gauge -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body items-center text-center">
          <h2 class="card-title text-2xl mb-6">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-6 h-6"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M3.75 13.5l10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75z"
              />
            </svg>
            VM Run Count
          </h2>
          <div class="flex justify-center items-center space-x-8">
            <div class="flex flex-col items-center">
              <div
                class="radial-progress text-primary text-6xl font-bold"
                style={"--value:#{min(100, (@status.running || 0) / 50)}; --size:12rem; --thickness:8px;"}
                role="progressbar"
                aria-valuenow={@status.running || 0}
                aria-valuemin="0"
                aria-valuemax="5000"
              >
                {@status.running || 0}
              </div>
              <div class="mt-4 text-lg font-semibold text-primary">Running VMs</div>
              <div class="text-sm text-base-content/60">out of 5000 max</div>
            </div>
            <div class="flex flex-col items-center">
              <div
                class="radial-progress text-secondary text-6xl font-bold"
                style={"--value:#{min(100, (@status.total || 0) / 50)}; --size:12rem; --thickness:8px;"}
                role="progressbar"
                aria-valuenow={@status.total || 0}
                aria-valuemin="0"
                aria-valuemax="5000"
              >
                {@status.total || 0}
              </div>
              <div class="mt-4 text-lg font-semibold text-secondary">Total VMs</div>
              <div class="text-sm text-base-content/60">out of 5000 max</div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
