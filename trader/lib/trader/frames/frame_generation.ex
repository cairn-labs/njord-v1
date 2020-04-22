defmodule Trader.Frames.FrameGeneration do
  alias Trader.Db
  require Logger

  def generate_frames(%FrameConfig{} = frame_config, num_frames) do
    case available_windows(frame_config) do
      [] ->
        {:error, :no_data_available}

      windows when length(windows) < num_frames ->
        Logger.warn("Attempting to collect more frames than available windows.")
        extract_frames(windows, frame_config)

      windows ->
        extract_frames(Enum.take_random(windows, num_frames), frame_config)
    end
  end

  defp available_windows(
         %FrameConfig{
           frame_width_ms: frame_width_ms,
           feature_configs: feature_configs,
           label_configs: label_configs
         } = frame_config
       ) do
    required_types =
      feature_configs
      |> Enum.filter(&has_interpolation_limit/1)
      |> Enum.map(fn %FeatureConfig{data_point_type: type} -> type end)
      |> Enum.into(MapSet.new())

    feature_configs
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
  end

  defp available_windows_by_type(%FeatureConfig{interpolate_strategy: nil}, _) do
    []
  end

  defp available_windows_by_type(
         %FeatureConfig{
           interpolate_strategy: %InterpolateStrategy{max_interpolation_time_diff_ms: 0}
         },
         _
       ) do
    []
  end

  defp available_windows_by_type(
         %FeatureConfig{
           data_point_type: data_point_type,
           interpolate_strategy: %InterpolateStrategy{
             max_interpolation_time_diff_ms: max_time_diff
           }
         } = config,
         frame_width_ms
       ) do
    selector = Trader.Selectors.from_feature_config(config)

    result =
      Db.DataPoints.get_available_windows(
        data_point_type,
        max_time_diff,
        frame_width_ms,
        selector
      )

    Logger.debug(
      "Found #{length(result)} windows for type #{Atom.to_string(data_point_type)} " <>
        "and selector #{selector}"
    )

    Enum.map(result, fn d -> {d, data_point_type} end)
  end

  defp has_interpolation_limit(%FeatureConfig{
         interpolate_strategy: %InterpolateStrategy{max_interpolation_time_diff_ms: 0}
       }),
       do: false

  defp has_interpolation_limit(_), do: true

  defp extract_frames(window_starts, %FrameConfig{} = config) do
    frames =
      for start <- window_starts do
        extract_frame(start, config)
      end

    {:ok, frames}
  end

  defp extract_frame(window_start, %FrameConfig{
         feature_configs: configs,
         frame_width_ms: frame_width_ms
       }) do
    components =
      for config <- configs do
        selector = Trader.Selectors.from_feature_config(config)

        data_points =
          Db.DataPoints.get_frame_component(config, window_start, frame_width_ms, selector)
          |> Enum.map(&DataPoint.decode/1)

        FrameComponent.new(data_point_type: config.data_point_type, data: data_points)
      end

    DataFrame.new(components: components)
  end
end
