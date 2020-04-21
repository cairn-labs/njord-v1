defmodule Trader.Frames.FrameGeneration do
  alias Trader.Db
  require Logger

  def generate_frames(%FrameConfig{} = frame_config, num_frames) do
    windows = available_windows(frame_config)
    {:ok, windows}
  end

  defp available_windows(
         %FrameConfig{
           frame_width_ms: frame_width_ms,
           vectorization_configs: vectorization_configs,
           label_configs: label_configs
         } = frame_config
       ) do
    required_types =
      vectorization_configs
      |> Enum.filter(&has_interpolation_limit/1)
      |> Enum.map(fn %VectorizationConfig{data_point_type: type} -> type end)
      |> Enum.into(MapSet.new())

    windows =
      vectorization_configs
      |> Enum.flat_map(fn c -> available_windows_by_type(c, frame_width_ms) end)
      |> Enum.group_by(fn {ts, type} -> ts end)
      |> Stream.map(fn {k, values} ->
        {k,
         Enum.flat_map(values, fn
           {ts, type} ->
             if MapSet.member?(required_types, type) do
               [type]
             else
               []
             end
         end)}
      end)
      |> Stream.filter(fn {ts, types} ->
        MapSet.size(Enum.into(types, MapSet.new())) == MapSet.size(required_types)
      end)
      |> Enum.map(fn {ts, _} -> ts end)

    Logger.info(inspect(windows))
    windows
  end

  defp available_windows_by_type(%VectorizationConfig{interpolate_strategy: nil}, _) do
    []
  end

  defp available_windows_by_type(
         %VectorizationConfig{
           interpolate_strategy: %InterpolateStrategy{max_interpolation_time_diff_ms: 0}
         },
         _
       ) do
    []
  end

  defp available_windows_by_type(
         %VectorizationConfig{
           data_point_type: data_point_type,
           interpolate_strategy: %InterpolateStrategy{
             max_interpolation_time_diff_ms: max_time_diff
           }
         },
         frame_width_ms
       ) do
    result = Db.DataPoints.get_available_windows(data_point_type, max_time_diff, frame_width_ms)
    Logger.debug("Found #{length(result)} windows for type #{Atom.to_string(data_point_type)}")
    Enum.map(result, fn d -> {d, data_point_type} end)
  end

  defp has_interpolation_limit(%VectorizationConfig{
         interpolate_strategy: %InterpolateStrategy{max_interpolation_time_diff_ms: 0}
       }),
       do: false

  defp has_interpolation_limit(_), do: true
end
