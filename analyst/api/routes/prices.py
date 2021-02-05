from fastapi import APIRouter
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel
from base64 import b64decode, b64encode

from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig
from analyst.prediction import predict


router = APIRouter()


class PricePredictionRequest(BaseModel):
    frame: str
    config: str


@router.post("/predict", response_class=PlainTextResponse)
def query(request: PricePredictionRequest) -> bytes:
    data_frame = DataFrame()
    data_frame.ParseFromString(b64decode(request.frame))
    prediction_config = PredictionModelConfig()
    prediction_config.ParseFromString(b64decode(request.config))
    prediction = predict(prediction_config, data_frame)
    return b64encode(prediction.SerializeToString())