defmodule Bon.VMSupervisor do
  use DynamicSupervisor

  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @hard_limit 5000
  def add(count) do
    Logger.info("Adding #{count} VMs")
    %{workers: current} = DynamicSupervisor.count_children(__MODULE__)

    if current + count <= @hard_limit do
      1..count
      |> Enum.each(fn _ ->
        identifier = Process.get("identifier", 1)
        disk_image = "/space/disks/#{identifier}.img"
        start_child(identifier, disk_image)
        Process.put("identifier", identifier + 1)
      end)
    end
  end

  def remove(count) do
    Logger.info("Removing #{count} VMs")

    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.take(count)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end)
    |> tap(fn _ ->
      Phoenix.PubSub.broadcast(Bon.PubSub, "status", :change)
    end)
  end

  def start_child(identifier, disk_image) do
    spec = {Bon.VM, identifier: identifier, disk_image: disk_image}

    DynamicSupervisor.start_child(__MODULE__, spec)
    |> tap(fn _ ->
      Phoenix.PubSub.broadcast(Bon.PubSub, "status", :change)
    end)
  end

  def stop_child(identifier) do
    DynamicSupervisor.terminate_child(__MODULE__, "vm-#{identifier}")
    |> tap(fn _ ->
      Phoenix.PubSub.broadcast(Bon.PubSub, "status", :change)
    end)
  end

  def status do
    counts = DynamicSupervisor.count_children(__MODULE__)
    children = DynamicSupervisor.which_children(__MODULE__)
    start_count = Enum.count(children)

    confirmed_count =
      children
      |> Enum.filter(fn {_, pid, _, _} ->
        Bon.VM.up?(pid)
      end)
      |> Enum.count()

    %{total: start_count, running: confirmed_count}
    |> IO.inspect()
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
