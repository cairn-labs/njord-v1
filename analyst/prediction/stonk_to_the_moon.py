from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from .price_prediction_model import PricePredictionModel
from analyst.vectorization.frame_vectorization import data_timestamps
from analyst.proto.data_point_pb2 import DataPointType
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.label_pb2 import Label
from analyst.proto.prediction_pb2 import Prediction
from analyst.proto.label_config_pb2 import LabelType


class StonkToTheMoonModel(PricePredictionModel):
    """This model just predicts that a given stock will be worth TEN MILLION DOLLARS,
    giving a strategy a very strong signal to buy said stock.
    """
    @staticmethod
    def name():
        return "stonk_to_the_moon"

    def build(self, prediction_model_config: PredictionModelConfig):
        self.frame_config_ = prediction_model_config.frame_config
        self.prediction_delay_ms_ = prediction_model_config.label_config.prediction_delay_ms
        assert len(self.frame_config_.feature_configs) == 1, "STONK TO THE MOON requires an input frame with exactly one stonk"
        self.ticker_ = self.frame_config_.feature_configs[0].stonk_aggregate_config.ticker

    def predict(self, data_frame: DataFrame) -> Label:
        timestamps = data_timestamps(data_frame, DataPointType.STONK_AGGREGATE)
        target_timestamp = timestamps[-1] + self.prediction_delay_ms_

        result = Prediction()
        label = result.labels.add()
        label.event_timestamp = target_timestamp
        label.value_decimal = "0"
        label.label_config.label_type = LabelType.STONK_PRICE
        label.label_config.stonk_price_config.ticker = self.ticker_
        return result