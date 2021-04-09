from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from .price_prediction_model import PricePredictionModel
from analyst.vectorization.frame_vectorization import data_timestamps, vectorize_frame
from analyst.proto.data_point_pb2 import DataPointType
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.label_pb2 import Label
from analyst.proto.prediction_pb2 import Prediction
from analyst.proto.label_config_pb2 import LabelType, LabelOptions
from analyst.stonk_util import TOP_STONKS

from scipy.stats import linregress
import numpy as np


MINIMUM_TOTAL_SCORE = 100
MINIMUM_RSQUARED = 0.5
MAXIMUM_PERCENT_ZEROS = 0.3
STONK_BLACKLIST = {'GME', 'GOOG'}  # cuz fuck GME and I'm not allowed to trade GOOG half the year

class SubredditTickerMentionMomentumModel(PricePredictionModel):
    """Literally just buys or sells depending on if a stonk is being talked about more or less.
    """
    @staticmethod
    def name():
        return "subreddit_ticker_mention_momentum"

    def build(self, prediction_model_config: PredictionModelConfig):
        self.frame_config_ = prediction_model_config.frame_config
        self.prediction_delay_ms_ = prediction_model_config.label_config.prediction_delay_ms
        assert len(self.frame_config_.feature_configs) == 1, (
            "Subreddit ticker mention momentum model requires an input frame with exactly "
            "one feature config of type SUBREDDIT_TOP_LISTING.")

    def predict(self, data_frame: DataFrame) -> Label:
        vectorized, _ = vectorize_frame(data_frame, self.frame_config_)
        timestamps = data_timestamps(data_frame, DataPointType.SUBREDDIT_TOP_LISTING)
        target_timestamp = timestamps[-1] + self.prediction_delay_ms_

        ticker_trajectories = {}
        total_counts = []
        for idx, window in enumerate(vectorized[0]):
            added_this_tick = set()
            total_counts.append(sum(int(c) for _, c in window))
            for t, c in window:
                if t in TOP_STONKS:
                    added_this_tick.add(t)
                    if t in ticker_trajectories:
                        ticker_trajectories[t].append(int(c))
                    else:
                        ticker_trajectories[t] = [0] * idx + [int(c)]
            for k in ticker_trajectories.keys():
                if k not in added_this_tick:
                    ticker_trajectories[k].append(0)


        moves = []
        for ticker, counts_over_time in ticker_trajectories.items():
            if (sum(counts_over_time) < MINIMUM_TOTAL_SCORE
                    or counts_over_time.count(0)/len(counts_over_time) > MAXIMUM_PERCENT_ZEROS):
                continue
            incidence = [c/t for c, t in zip(counts_over_time, total_counts)]
            result = linregress(timestamps, incidence)
            if result.rvalue**2 < MINIMUM_RSQUARED:
                continue

            moves.append((ticker, result.slope))

        result = Prediction()
        for ticker, slope in moves:
            if ticker.upper() in STONK_BLACKLIST:
                continue
            label = result.labels.add()
            label.event_timestamp = target_timestamp
            label.value_decimal = "-0.1" if slope < 0 else "0.1"
            label.label_config.label_type = LabelType.STONK_PRICE
            label.label_config.label_options = LabelOptions.RELATIVE_VALUE
            label.label_config.stonk_price_config.ticker = ticker.upper()
        return result
