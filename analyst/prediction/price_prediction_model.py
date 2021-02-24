from abc import ABCMeta, abstractmethod
from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.label_pb2 import Label
from analyst.proto.prediction_pb2 import Prediction


class PricePredictionModel(metaclass=ABCMeta):
    @staticmethod
    @abstractmethod
    def name():
        pass

    @abstractmethod
    def build(self, prediction_model_config: PredictionModelConfig):
        pass

    @abstractmethod
    def predict(self, data_frame: DataFrame) -> Label:
        pass