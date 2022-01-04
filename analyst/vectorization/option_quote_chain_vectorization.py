from analyst.proto.vectorization_strategy_pb2 import NBBO, VectorizationStrategy
from analyst.proto.data_point_pb2 import DataPoint
from analyst.proto.frame_component_pb2 import FrameComponent
from google.protobuf.text_format import MessageToString
import numpy as np

MAX_CHAIN_SIZE = 128


def option_quote_chain_feature_shape(format):
    if format == NBBO:
        return (MAX_CHAIN_SIZE, 5)
    else:
        raise NotImplementedError(f"Vectorization strategy {VectorizationStrategy.Name(format)} "
                                  "not supported for data point type OPTION_QUOTE_CHAIN.")


def vectorize_option_quote_chain_frame_component(component: FrameComponent, format):
    return np.asarray([
        vectorize_option_quote_chain(d, format) for d in component.data
    ])


def vectorize_option_quote_chain(data: DataPoint, format):
    assert format == NBBO
    chain = np.asarray([[q.symbol, q.bid, q.bidsz, q.ask, q.asksz]
                        for q in data.option_quote_chain.quote])
    chain.resize((MAX_CHAIN_SIZE, 5))
    return chain