from .fx_simple_linear_regression import FxSimpleLinearRegressionModel
from .stonk_to_the_moon import StonkToTheMoonModel
from .subreddit_ticker_mention_momentum import SubredditTickerMentionMomentumModel
# from .tensorflow_stonk_prediction import TensorflowStonkPredictionModel
from .find_mispriced_options_in_chain import FindMispricedOptionsInChainModel
from .macd_technical_model import MACDTechnicalModel
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from analyst.proto.prediction_pb2 import Prediction


__all_models = [
    FxSimpleLinearRegressionModel,
    StonkToTheMoonModel,
    SubredditTickerMentionMomentumModel,
    # TensorflowStonkPredictionModel,
    MACDTechnicalModel,
    FindMispricedOptionsInChainModel
]
__model_type_lookup = {m.name(): m for m in  __all_models}


def predict(prediction_model_config: PredictionModelConfig, data_frame: DataFrame) -> Prediction:
    model = __model_type_lookup[prediction_model_config.name]()
    model.build(prediction_model_config)
    return model.predict(data_frame)