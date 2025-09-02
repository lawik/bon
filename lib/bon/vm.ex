defmodule Bon.VM do
  use GenServer
  use Phoenix.VerifiedRoutes, endpoint: BonWeb.Endpoint, router: BonWeb.Router

  def start_link(opts) do
    identifier = Keyword.get(opts, :identifier)
    GenServer.start_link(__MODULE__, opts, name: {:global, name(identifier)})
  end

  def name(identifier) do
    "vm-#{identifier}"
  end

  def init(opts) do
    identifier = Keyword.get(opts, :identifier)
    disk_image = Keyword.get(opts, :disk_image)

    {:ok, pid} =
      if System.get_env("MOCK", "false") == "true" do
        spawn(fn ->
          :timer.sleep(1500)
          Req.post(url(~p"/api/status/#{identifier}"))
        end)

        Agent.start_link(fn -> :ok end)
      else
        MuonTrap.Daemon.start_link("qemu-system-aarch64", args(identifier, disk_image), [])
      end

    {:ok, %{identifier: opts[:identifier], pid: pid, started?: false}}
  end

  def report(identifier) do
    GenServer.call({:global, name(identifier)}, :report)
  rescue
    _ ->
      :ok
  end

  def up?(pid) when is_pid(pid) do
    GenServer.call(pid, :up?)
  end

  def up?(identifier) do
    GenServer.call({:global, name(identifier)}, :up?)
  end

  @impl GenServer
  def handle_call(:report, _from, state) do
    Phoenix.PubSub.broadcast(Bon.PubSub, "status", :change)
    {:reply, :ok, %{state | started?: true}}
  end

  def handle_call(:up?, _from, state) do
    {:reply, state.started?, state}
  end

  defp loader_path() do
    System.get_env("LITTLE_LOADER_PATH", Path.expand("../little_loader.elf"))
  end

  defp args(identifier, disk_image) do
    macaddr = Bon.MacAddress.consistent(identifier)

    [
      "-machine",
      "virt,accel=kvm",
      "-cpu",
      "host",
      "-smp",
      "1",
      "-m",
      "110M",
      "-kernel",
      loader_path(),
      "-netdev",
      "user,id=eth0",
      "-device",
      "virtio-net-device,netdev=eth0,mac=#{macaddr}",
      "-global",
      "virtio-mmio.force-legacy=false",
      "-drive",
      "if=none,file=#{disk_image},format=raw,id=vdisk",
      "-device",
      "virtio-blk-device,drive=vdisk,bus=virtio-mmio-bus.0",
      "-nographic"
    ]
  end
end
