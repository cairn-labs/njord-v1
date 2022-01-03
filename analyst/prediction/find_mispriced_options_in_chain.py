from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from .price_prediction_model import PricePredictionModel
from analyst.vectorization.frame_vectorization import data_timestamps, vectorize_frame
from analyst.proto.data_point_pb2 import DataPointType
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.label_pb2 import Label


class FindMispricedOptionsInChainModel(PricePredictionModel):
    """Looks through option chain for a given underlying and looks for scalping opportunities.
    """
    @staticmethod
    def name():
        return "find_mispriced_options_in_chain"

    def build(self, prediction_model_config: PredictionModelConfig):
        self.frame_config_ = prediction_model_config.frame_config
        self.prediction_delay_ms_ = prediction_model_config.label_config.prediction_delay_ms
        assert len(self.frame_config_.feature_configs) == 1, (
            "Find Mispriced Options in Chain model requires an input frame with exactly "
            "one feature config of type OPTION_QUOTE.")

    def predict(self, data_frame: DataFrame) -> Label:
        vectorized, _ = vectorize_frame(data_frame, self.frame_config_)
        #timestamps = data_timestamps(data_frame, DataPointType.OPTION_QUOTE_CHAIN)
        #target_timestamp = timestamps[-1] + self.prediction_delay_ms_
        print("Vectorized:")
        print(vectorized)
        return Label()