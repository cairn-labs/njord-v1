from .fx_simple_linear_regression import FxSimpleLinearRegressionModel
from .stonk_to_the_moon import StonkToTheMoonModel
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from analyst.proto.label_pb2 import Label


__all_models = [
    FxSimpleLinearRegressionModel,
    StonkToTheMoonModel
]
__model_type_lookup = {m.name(): m for m in  __all_models}


def predict(prediction_model_config: PredictionModelConfig, data_frame: DataFrame) -> Label:
    model = __model_type_lookup[prediction_model_config.name]()
    model.build(prediction_model_config)
    return model.predict(data_frame)