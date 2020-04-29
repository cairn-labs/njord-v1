defmodule Trader.Frames.StratifiedSampleWindows do
  def available_windows(%FrameConfig{
        frame_width_ms: frame_width_ms,
        feature_configs: feature_configs,
        num_frames_requested: num_frames,
        label_config: %{label_type: :FX_RATE},
        sampling_strategy: %{stratified_random_window_params: sampling_params}
      }) do
    :ok
  end
end
