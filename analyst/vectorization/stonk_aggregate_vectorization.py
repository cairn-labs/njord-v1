from analyst.proto.vectorization_strategy_pb2 import PRICE_ONLY, PRICE_AND_VOLUME, STOCK_DATA_FRAME, VectorizationStrategy
from analyst.proto.data_point_pb2 import DataPoint
from analyst.proto.frame_component_pb2 import FrameComponent
from analyst.price_util import get_price_from_stonk_aggregate
import numpy as np
from stockstats import StockDataFrame
import pandas as pd


def stonk_aggregate_feature_shape(format):
    if format == PRICE_ONLY:
        return (1,)
    elif format == PRICE_AND_VOLUME:
        return (2,)
    elif format == STOCK_DATA_FRAME:
        return (5,)
    else:
        raise NotImplementedError(f"Vectorization strategy {VectorizationStrategy.Name(format)} "
                                  "not supported for data point type STONK_AGGREGATE.")

def vectorize_stonk_aggregate_frame_component(component: FrameComponent, format):
    return np.asarray([
        vectorize_stonk_aggregate(d, format) for d in component.data
    ])


def vectorize_stonk_aggregate(data: DataPoint, format):
    if format == PRICE_ONLY:
        return np.asarray([get_price_from_stonk_aggregate(data)])
    elif format == PRICE_AND_VOLUME:
        return np.asarray([get_price_from_stonk_aggregate(data), data.stonk_aggregate.volume])
    elif format == STOCK_DATA_FRAME:
        a = data.stonk_aggregate
        return np.asarray([a.open_price, a.close_price, a.high_price, a.low_price, a.volume])


def to_stock_dataframe(timestamps, numpy_dataframe):
    return StockDataFrame.retype(pd.DataFrame(data=numpy_dataframe,
                                              index=timestamps,
                                              columns=['open', 'close', 'high', 'low', 'volume']))