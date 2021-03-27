from .price_prediction_model import PricePredictionModel
from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.label_pb2 import Label
from analyst.proto.data_point_pb2 import DataPointType
from analyst.vectorization.frame_vectorization import data_timestamps, vectorize_frame
from analyst.config import MODELS_DIR
from analyst.proto.prediction_pb2 import Prediction
from analyst.proto.label_config_pb2 import LabelType, LabelOptions
import tensorflow as tf
import os
import numpy as np

model = tf.keras.models.load_model(os.path.join(MODELS_DIR, "model0.savedmodel"))


class TensorflowStonkPredictionModel(PricePredictionModel):
    """Purely technical strategy that runs a vectorized frame of stonk aggregates
    through a trained Tensorflow model and returns a prediction.
    """

    @staticmethod
    def name():
        return "tensorflow_stonk_prediction"

    def build(self, prediction_model_config: PredictionModelConfig):
        self.frame_config_ = prediction_model_config.frame_config
        self.prediction_delay_ms_ = prediction_model_config.label_config.prediction_delay_ms
        assert len(self.frame_config_.feature_configs) == 1, (
            "Tensorflow stonk prediction model requires an input frame with exactly "
            "one feature config of type STONK_AGGREGATE.")
        self.ticker_ = self.frame_config_.feature_configs[0].stonk_aggregate_config.ticker

    def predict(self, data_frame: DataFrame) -> Label:
        vectorized, _ = vectorize_frame(data_frame, self.frame_config_)
        print('vec', vectorized)
        timestamps = data_timestamps(data_frame, DataPointType.STONK_AGGREGATE)
        target_timestamp = timestamps[-1] + self.prediction_delay_ms_
        predicted_class = np.argmax(model.predict({'stonk': np.asarray([vectorized[0]])}), axis=1)
        # 0 is down, 1 is flat, 2 is up
        result = Prediction()
        if predicted_class != 1:
            label = result.labels.add()
            label.event_timestamp = target_timestamp
            label.value_decimal = "-0.1" if predicted_class == 0 else "0.1"
            label.label_config.label_type = LabelType.STONK_PRICE
            label.label_config.label_options = LabelOptions.RELATIVE_VALUE
            label.label_config.stonk_price_config.ticker = self.ticker_.upper()
        return result