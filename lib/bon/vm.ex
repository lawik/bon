defmodule Bon.VM do
  use GenServer

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
        Agent.start_link(fn -> :ok end)
      else
      MuonTrap.Daemon.start_link("qemu-system-aarch64", args(identifier, disk_image), [])
      end

    {:ok, %{identifier: opts[:identifier], pid: pid}}
  end

  defp loader_path() do
    System.get_env("LITTLE_LOADER_PATH", Path.expand("../little_loader.elf"))
  end

  defp args(identifier, disk_image) do

    macaddr = Bon.MacAddress.consistent(identifier)
    [
      "-machine", "virt,accel=kvm",
      "-cpu", "host",
      "-smp", "1",
      "-m", "110M",
      "-kernel", loader_path(),
      "-netdev", "user,id=eth0",
      "-device", "virtio-net-device,netdev=eth0,mac=#{macaddr}",
      "-global", "virtio-mmio.force-legacy=false",
      "-drive", "if=none,file=#{disk_image},format=raw,id=vdisk",
      "-device", "virtio-blk-device,drive=vdisk,bus=virtio-mmio-bus.0",
      "-nographic"
    ]
  end
end
