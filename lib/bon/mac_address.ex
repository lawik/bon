defmodule Bon.MacAddress do
  def consistent(num) do
    num
    |> Integer.to_string(16)
    |> String.pad_leading(12, "0")
    |> :binary.bin_to_list()
    |> Enum.chunk_every(2)
    |> Enum.map(&IO.iodata_to_binary/1)
    |> Enum.join(":")
  end

  def to_integer(mac) do
    mac
    |> String.replace(":", "")
    |> Integer.parse(16)
    |> elem(0)
  end
end
