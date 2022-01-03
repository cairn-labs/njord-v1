from analyst.proto.vectorization_strategy_pb2 import NBBO, VectorizationStrategy
from analyst.proto.data_point_pb2 import DataPoint
from analyst.proto.frame_component_pb2 import FrameComponent
import numpy as np


def option_quote_feature_shape(format):
    if format == NBBO:
        return (2, 2)
    else:
        raise NotImplementedError(f"Vectorization strategy {VectorizationStrategy.Name(format)} "
                                  "not supported for data point type OPTION_QUOTE.")


def vectorize_option_quote_frame_component(component: FrameComponent, format):
    return np.asarray([
        vectorize_option_quote(d, format) for d in component.data
    ])


def vectorize_option_quote(data: DataPoint, format):
    assert format == NBBO
    return np.asarray([[data.option_quote.bid, data.option_quote.bidsz], [data.option_quote.ask, data.option_quote.asksz]])