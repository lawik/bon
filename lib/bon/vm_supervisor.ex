defmodule Bon.VMSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_child(identifier, disk_image) do
    spec = {Bon.VM, identifier: identifier, disk_image: disk_image}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_child(identifier) do
    DynamicSupervisor.terminate_child(__MODULE__, "vm-#{identifier}")
    Bon.VM.stop(identifier)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
