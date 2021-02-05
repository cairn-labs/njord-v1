from .simple_linear_regression import SimpleLinearRegressionModel
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from analyst.proto.label_pb2 import Label


__all_models = [
    SimpleLinearRegressionModel
]
__model_type_lookup = {m.name(): m for m in  __all_models}


def predict(prediction_model_config: PredictionModelConfig, data_frame: DataFrame) -> Label:
    model = __model_type_lookup[prediction_model_config.name]()
    model.build(prediction_model_config)
    return model.predict(data_frame)