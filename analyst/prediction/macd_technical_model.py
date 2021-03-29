from .price_prediction_model import PricePredictionModel
from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.label_pb2 import Label
from analyst.proto.data_point_pb2 import DataPointType
from analyst.vectorization.frame_vectorization import data_timestamps, vectorize_frame
from analyst.vectorization.stonk_aggregate_vectorization import to_stock_dataframe
from analyst.proto.prediction_pb2 import Prediction
from analyst.proto.label_config_pb2 import LabelType, LabelOptions


class MACDTechnicalModel(PricePredictionModel):
    """Purely technical strategy based on MACD indicator
    """

    @staticmethod
    def name():
        return "macd_technical_model"

    def build(self, prediction_model_config: PredictionModelConfig):
        self.frame_config_ = prediction_model_config.frame_config
        self.prediction_delay_ms_ = prediction_model_config.label_config.prediction_delay_ms
        assert len(self.frame_config_.feature_configs) == 1, (
            "MACD stonk prediction model requires an input frame with exactly "
            "one feature config of type STONK_AGGREGATE.")
        self.ticker_ = self.frame_config_.feature_configs[0].stonk_aggregate_config.ticker

    def predict(self, data_frame: DataFrame) -> Label:
        vectorized, _ = vectorize_frame(data_frame, self.frame_config_)
        timestamps = data_timestamps(data_frame, DataPointType.STONK_AGGREGATE)
        target_timestamp = timestamps[-1] + self.prediction_delay_ms_
        stock_dataframe = to_stock_dataframe(timestamps, vectorized[0])
        macd = stock_dataframe['macd'].to_numpy()
        macds = stock_dataframe['macds'].to_numpy()
        result = Prediction()
        if macd[-1] > macds[-1] and macd[-2] <= macds[-2]:
            # Crossover buy
            label = result.labels.add()
            label.event_timestamp = target_timestamp
            label.value_decimal = "0.1"
            label.label_config.label_type = LabelType.STONK_PRICE
            label.label_config.label_options = LabelOptions.RELATIVE_VALUE
            label.label_config.stonk_price_config.ticker = self.ticker_.upper()
        elif macd[-1] < macds[-1] and macd[-2] >= macds[-2]:
            # Crossover sell
            label = result.labels.add()
            label.event_timestamp = target_timestamp
            label.value_decimal = "-0.1"
            label.label_config.label_type = LabelType.STONK_PRICE
            label.label_config.label_options = LabelOptions.RELATIVE_VALUE
            label.label_config.stonk_price_config.ticker = self.ticker_.upper()
        return result
