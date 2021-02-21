from analyst.proto.vectorization_strategy_pb2 import PRICE_ONLY
from analyst.proto.data_point_pb2 import DataPoint
from analyst.proto.frame_component_pb2 import FrameComponent
from analyst.price_util import get_price_from_stonk_aggregate
import numpy as np


def stonk_aggregate_feature_shape(format):
    assert format == PRICE_ONLY
    return (1,)


def vectorize_stonk_aggregate_frame_component(component: FrameComponent, format):
    return np.asarray([
        vectorize_stonk_aggregate(d, format) for d in component.data
    ])


def vectorize_stonk_aggregate(data: DataPoint, format):
    assert format == PRICE_ONLY
    return np.asarray([get_price_from_stonk_aggregate(data)])