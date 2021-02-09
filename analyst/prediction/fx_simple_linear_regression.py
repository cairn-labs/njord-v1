from .price_prediction_model import PricePredictionModel
from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from analyst.proto.data_point_pb2 import DataPointType
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.label_pb2 import Label
from analyst.proto.label_config_pb2 import LabelType
from analyst.vectorization.frame_vectorization import vectorize_frame, data_timestamps
from scipy.stats import linregress
import numpy as np


class FxSimpleLinearRegressionModel(PricePredictionModel):
    @staticmethod
    def name():
        return "fx_simple_linear_regression"

    def build(self, prediction_model_config: PredictionModelConfig):
        self.frame_config_ = prediction_model_config.frame_config
        assert len(self.frame_config_.feature_configs) == 1, "Simple linear regression model requires exactly one feature"
        self.data_point_type_ = self.frame_config_.feature_configs[0].data_point_type
        assert self.data_point_type_ == DataPointType.L2_ORDER_BOOK
        self.product_ = self.frame_config_.feature_configs[0].l2_order_book_config.product
        self.prediction_delay_ms_ = prediction_model_config.label_config.prediction_delay_ms

    def predict(self, data_frame: DataFrame) -> Label:
        vectorized = vectorize_frame(data_frame, self.frame_config_)
        timestamps = data_timestamps(data_frame, self.data_point_type_)
        result = linregress(timestamps, np.ndarray.flatten(vectorized[0]))
        target_timestamp = timestamps[-1] + self.prediction_delay_ms_
        prediction = result.slope*target_timestamp + result.intercept

        label = Label()
        label.event_timestamp = target_timestamp
        label.value_decimal = str(prediction)
        label.label_config.label_type = LabelType.FX_RATE
        label.label_config.fx_rate_config.product.CopyFrom(self.product_)
        return label