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
    vectorization_configs
    |> Enum.map(fn c -> available_windows_by_type(c, frame_width_ms) end)
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
    result
  end
end
