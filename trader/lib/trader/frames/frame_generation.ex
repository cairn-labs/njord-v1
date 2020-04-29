defmodule Trader.Frames.FrameGeneration do
  alias Trader.Db
  alias Trader.Frames.LabelExtraction
  require Logger

  def generate_frames(
        %FrameConfig{
          num_frames_requested: num_frames
        } = frame_config
      ) do
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

  defp available_windows(%FrameConfig{
         frame_width_ms: frame_width_ms,
         feature_configs: feature_configs,
         sampling_strategy: %{sampling_strategy_type: :RANDOM_WINDOW}
       }) do
    required_types =
      feature_configs
      |> Enum.filter(&has_interpolation_limit/1)
      |> Enum.map(fn %FeatureConfig{data_point_type: type} -> type end)
      |> Enum.into(MapSet.new())

    feature_configs
    |> Enum.flat_map(fn c -> available_windows_by_type(c, frame_width_ms) end)
    |> Enum.group_by(fn {ts, _type} -> ts end)
    |> Stream.map(fn {k, values} ->
      {k,
       Enum.flat_map(values, fn
         {_ts, type} ->
           if MapSet.member?(required_types, type) do
             [type]
           else
             []
           end
       end)}
    end)
    |> Stream.filter(fn {_ts, types} ->
      MapSet.size(Enum.into(types, MapSet.new())) == MapSet.size(required_types)
    end)
    |> Enum.map(fn {ts, _} -> ts end)
  end

  defp available_windows(%FrameConfig{
         frame_width_ms: frame_width_ms,
         label_config: %{
           label_type: :FX_RATE,
           prediction_delay_ms: prediction_delay_ms,
           fx_rate_config: %{
             movement_minimum_percent_change: price_change_amount
           }
         },
         sampling_strategy: %{stratified_random_window_params: sampling_params}
       }) do
    window_starts_with_probability =
      sampling_params.target_label_probability
      |> Enum.filter(fn %{target_probability: p} -> p > 0 end)
      |> Enum.map(fn %{label_value: label_value, target_probability: probability} ->
        {Db.DataPoints.get_windows_by_price_change(
           Trader.Frames.LabelExtraction.label_to_direction(:FX_RATE, label_value),
           price_change_amount,
           frame_width_ms,
           prediction_delay_ms
         ), probability}
      end)

    min_quotient =
      window_starts_with_probability
      |> Enum.map(fn {times, p} -> length(times) / p end)
      |> Enum.min()

    window_starts_with_probability
    |> Enum.flat_map(fn {times, p} -> Enum.take_random(times, floor(min_quotient * p)) end)
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
      window_starts
      |> Enum.flat_map(fn start ->
        try do
          frame = extract_frame(start, config)
          [frame]
        rescue
          e in FunctionClauseError ->
            []
        end
      end)

    {:ok, frames}
  end

  defp extract_frame(
         window_start,
         %FrameConfig{
           frame_width_ms: frame_width_ms,
           label_config:
             %LabelConfig{
               prediction_delay_ms: prediction_delay_ms
             } = label_config
         } = frame_config
       ) do
    components = extract_frame_components(window_start, frame_config)

    label =
      window_start
      |> DateTime.add(frame_width_ms, :millisecond)
      |> DateTime.add(prediction_delay_ms, :millisecond)
      |> LabelExtraction.get_label(label_config)

    DataFrame.new(components: components, label: label)
  end

  defp extract_frame_components(window_start, %FrameConfig{
         feature_configs: feature_configs,
         frame_width_ms: frame_width_ms
       }) do
    for feature_config <- feature_configs do
      selector = Trader.Selectors.from_feature_config(feature_config)

      data_points =
        Db.DataPoints.get_frame_component(
          feature_config,
          window_start,
          frame_width_ms,
          selector
        )
        |> Enum.map(&DataPoint.decode/1)

      FrameComponent.new(data_point_type: feature_config.data_point_type, data: data_points)
    end
  end
end
