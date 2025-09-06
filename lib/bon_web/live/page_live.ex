defmodule BonWeb.Live.PageLive do
  use BonWeb, :live_view

  @ksm_savings_path "/sys/kernel/mm/ksm/general_profit"

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
        ksm: %{savings: 0},
        memory: %{total: 0, used: 0},
        cpu: %{util: 0.0, load_avg1: 0, load_avg5: 0, load_avg15: 0},
        cpu_cores: [],
        form: to_form(%{"count" => to_string(status.running)})
      )

    {:ok, socket}
  end

  defp tick(t \\ 1) do
    Process.send_after(self(), :tick, t * 1000)
  end

  def handle_info(:tick, socket) do
    sysmem = :memsup.get_system_memory_data()
    total = Keyword.get(sysmem, :system_total_memory, 0)
    used = total - Keyword.get(sysmem, :available_memory, 0)

    ksm_savings =
      try do
      @ksm_savings_path
      |> File.read!()
      |> Sizeable.filesize()
      rescue
        _ ->
          "-"
  end

    # Get CPU load averages
    cpu_load_avg1 =
      case :cpu_sup.avg1() do
        {:error, _} -> 0
        load when is_integer(load) -> load
        _ -> 0
      end

    # Get detailed per-CPU utilization
    cpu_cores =
      case :cpu_sup.util([:per_cpu]) do
        {:badrpc, _} ->
          []

        cores when is_list(cores) ->
          cores
          |> Enum.map(fn {id, busy, _non_busy, _misc} ->
            %{
              id: id,
              utilization: busy
            }
          end)

        _ ->
          []
      end

    cpu_util = Enum.sum_by(cpu_cores, & &1.utilization) / Enum.count(cpu_cores)

    tick()

    {:noreply,
     assign(socket,
       ksm: %{savings: ksm_savings},
       memory: %{total: total, used: used},
       cpu: %{
         util: cpu_util,
         load_avg1: cpu_load_avg1,
       },
       cpu_cores: cpu_cores
     )}
  end

  def handle_info({:change, change}, %{assigns: %{refresh: nil}} = socket) do
    socket = update_change(change, socket)

    t =
      Task.async(fn ->
        Bon.VMSupervisor.status()
      end)

    {:noreply, assign(socket, refresh: t, dirty?: false)}
  end

  def handle_info({:change, change}, socket) do
    socket = update_change(change, socket)
    {:noreply, assign(socket, dirty?: true)}
  end

  def handle_info({_ref, result}, socket) do
    current_count = result.running || 0

    updated_socket =
      assign(socket, status: result, form: to_form(%{"count" => to_string(current_count)}))

    if socket.assigns.dirty? do
      t =
        Task.async(fn ->
          Bon.VMSupervisor.status()
        end)

      {:noreply, assign(updated_socket, refresh: t, dirty?: false)}
    else
      {:noreply, assign(updated_socket, refresh: nil, dirty?: false)}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  defp update_change(change, socket) do
    total = socket.assigns.status.total
    running = socket.assigns.status.running

    case change do
      :added ->
        assign(socket, status: %{socket.assigns.status | total: total + 1})

      :ready ->
        assign(socket, status: %{socket.assigns.status | running: running + 1})

      :removed ->
        assign(socket, status: %{socket.assigns.status | running: running - 1, total: total - 1})
    end
  end

  def handle_event("add", %{"count" => count}, socket) do
    count = String.to_integer(count)

    spawn(fn ->
      Bon.VMSupervisor.add(count)
    end)

    {:noreply, socket}
  end

  def handle_event("remove", %{"count" => count}, socket) do
    count = String.to_integer(count)

    spawn(fn ->
      Bon.VMSupervisor.remove(count)
    end)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <!-- Header -->

      <div class="stats shadow w-full">
        <!-- CPU Stats -->
        <div class="stat">
          <div class="stat-title">CPU Utilization</div>
          <div class="stat-value text-warning">
            {:erlang.float_to_binary(@cpu.util, decimals: 1)}%
          </div>
        </div>
        <div class="stat">
          <div class="stat-title">Load Avg (1m)</div>
          <div class="stat-value text-info">
            {(@cpu.load_avg1 / 256) |> :erlang.float_to_binary(decimals: 2)}
          </div>
        </div>
        <!-- Memory Stats -->
        <div class="stat">
          <div class="stat-title">Total Memory</div>
          <div class="stat-value text-primary">{Sizeable.filesize(@memory.total)}</div>
        </div>

        <div class="stat">
          <div class="stat-title">Used Memory</div>
          <div class="stat-value text-secondary">{Sizeable.filesize(@memory.used)}</div>
        </div>

        <div class="stat">
          <div class="stat-title">Memory Usage</div>
          <div class="stat-value text-accent">
            {round(@memory.used / max(@memory.total, 1) * 100)}%
          </div>
        </div>
        <!-- KSM savings -->
        <div class="stat">
          <div class="stat-title">KSM savings</div>
          <div class="stat-value text-primary">{@ksm.savings}</div>
        </div>
      </div>


    <!-- CPU Cores Visualization -->
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
                d="M8.25 3v1.5M4.5 8.25H3m18 0h-1.5M4.5 12H3m18 0h-1.5m-16.5 3.75H3m18 0h-1.5M8.25 19.5V21M12 3v1.5m0 15V21m3.75-18v1.5m0 15V21"
              />
            </svg>
            CPU Cores ({length(@cpu_cores)} cores)
          </h2>

          <%= if length(@cpu_cores) > 0 do %>
            <div class="grid gap-1 grid-cols-32">
              <%= for core <- @cpu_cores do %>
                <div
                  class={[
                    "w-full h-3 rounded-sm border border-base-300 transition-colors duration-300",
                    cond do
                      core.utilization >= 80 -> "bg-red-500"
                      core.utilization >= 60 -> "bg-orange-500"
                      core.utilization >= 30 -> "bg-yellow-500"
                      core.utilization >= 10 -> "bg-green-500"
                      true -> "bg-gray-300"
                    end
                  ]}
                  title={"Core #{core.id}: #{:erlang.float_to_binary(core.utilization, decimals: 1)}%"}
                >
                </div>
              <% end %>
            </div>

    <!-- Legend -->
            <div class="mt-4 flex flex-wrap gap-4 text-sm">
              <div class="flex items-center gap-2">
                <div class="w-3 h-3 bg-gray-300 rounded-sm border border-base-300"></div>
                <span>Idle (0-10%)</span>
              </div>
              <div class="flex items-center gap-2">
                <div class="w-3 h-3 bg-green-500 rounded-sm border border-base-300"></div>
                <span>Low (10-30%)</span>
              </div>
              <div class="flex items-center gap-2">
                <div class="w-3 h-3 bg-yellow-500 rounded-sm border border-base-300"></div>
                <span>Medium (30-60%)</span>
              </div>
              <div class="flex items-center gap-2">
                <div class="w-3 h-3 bg-orange-500 rounded-sm border border-base-300"></div>
                <span>High (60-80%)</span>
              </div>
              <div class="flex items-center gap-2">
                <div class="w-3 h-3 bg-red-500 rounded-sm border border-base-300"></div>
                <span>Critical (80%+)</span>
              </div>
            </div>
          <% else %>
            <div class="text-center py-8 text-base-content/60">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="w-12 h-12 mx-auto mb-2"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"
                />
              </svg>
              <p>CPU core data unavailable</p>
              <p class="text-xs mt-1">Detailed CPU monitoring may not be supported on this system</p>
            </div>
          <% end %>
        </div>
      </div>

    <!-- Run Count Gauge -->
      <div class="card bg-base-100 ">
        <div class="card-body items-center text-center">
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
                <button class="btn btn-success btn-sm" phx-click="add" phx-value-count="1000">
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
                  1000
                </button>
              </div>
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
                <button class="btn btn-error btn-sm" phx-click="remove" phx-value-count="1000">
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
                  1000
                </button>
              </div>
            </div>
          </div>
          <div class="flex justify-center items-center space-x-8 mt-16">
            <div class="flex flex-col items-center" id="vm-run-count">
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
            <div class="flex flex-col items-center" id="vm-total-count">
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
