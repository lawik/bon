defmodule Bon.VMSupervisor do
  use DynamicSupervisor

  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg)
  end

  @vm_supervisor Bon.VMPartitionSupervisor
  @hard_limit 5000
  def add(count) do
    Logger.info("Adding #{count} VMs")
    %{workers: current} = PartitionSupervisor.count_children(@vm_supervisor)

    if current + count <= @hard_limit do
      count
      |> available_identifiers()
      |> Task.async_stream(fn identifier ->
        disk_image = "/space/disks/#{identifier}.img"
        start_child(identifier, disk_image)
      end, ordered: false, timeout: 360_000)
      |> Stream.run()
    end
  end

  def available_identifiers(count) do
    1..count
    |> Enum.reduce({1, []}, fn _, {current, available} ->
      valid = find_next(current)
      {valid + 1, [valid | available]}
    end)
    |> elem(1)
    |> Enum.sort()
  end

  defp find_next(num) do
    case :global.whereis_name(name(num)) do
      :undefined ->
        num
      pid when is_pid(pid) ->
        find_next(num + 1)
    end
  end

  def remove(count) do
    Logger.info("Removing #{count} VMs")

    PartitionSupervisor.which_children(@vm_supervisor)
    |> Enum.flat_map(fn {_, pid, :supervisor, _} ->
      DynamicSupervisor.which_children(pid)
      |> Enum.map(fn child ->
        {pid, child}
      end)
    end)
    |> Enum.take(count)
    |> Enum.each(fn {supervisor, {_, pid, _, _}} ->
      DynamicSupervisor.terminate_child(supervisor, pid) |> IO.inspect()
      Phoenix.PubSub.broadcast(Bon.PubSub, "status", {:change, :removed})
    end)
  end

  def start_child(identifier, disk_image) do
    spec = {Bon.VM, identifier: identifier, disk_image: disk_image}

    DynamicSupervisor.start_child(via(), spec)
    |> tap(fn _ ->
      Phoenix.PubSub.broadcast(Bon.PubSub, "status", {:change, :added})
    end)
  end

  def stop_child(identifier) do
    DynamicSupervisor.terminate_child(via(), name(identifier))
    |> tap(fn _ ->
      Phoenix.PubSub.broadcast(Bon.PubSub, "status", {:change, :removed})
    end)
  end

  defp name(identifier) do
    "vm-#{identifier}"
  end

  def status do
    counts = PartitionSupervisor.count_children(@vm_supervisor)
    supervisors = PartitionSupervisor.which_children(@vm_supervisor)

    children =
      supervisors
      |> Enum.flat_map(fn {_, pid, :supervisor, _} ->
        DynamicSupervisor.which_children(pid)
      end)

    start_count = Enum.count(children)

    confirmed_count =
      children
      |> Enum.filter(fn {_, pid, _, _} = child ->
        Bon.VM.up?(pid)
      end)
      |> Enum.count()

    %{total: start_count, running: confirmed_count}
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp via do
    {:via, PartitionSupervisor, {@vm_supervisor, self()}}
  end

  defp via(pid) do
    {:via, PartitionSupervisor, {@vm_supervisor, pid}}
  end
end
