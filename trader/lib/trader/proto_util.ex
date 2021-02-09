defmodule Trader.ProtoUtil do
  def parse_text_format(text_format_filename, proto_module, proto_file) do
    proto_name = List.last(String.split("#{proto_module}", "."))

    proto_definitions_dir =
      Application.app_dir(:trader, "priv")
      |> Path.join("proto_definitions")

    command = "protoc --encode=#{proto_name} #{proto_file} < '#{text_format_filename}'"
    {binary_format, 0} = System.cmd("/bin/sh", ["-c", command], cd: proto_definitions_dir)

    binary_format
    |> proto_module.decode()
  end
end
