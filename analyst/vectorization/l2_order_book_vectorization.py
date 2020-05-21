from analyst.proto.frame_component_pb2 import FrameComponent
from analyst.proto.l2_order_book_pb2 import L2OrderBookEntry
from analyst.proto.data_point_pb2 import DataPoint
from analyst.proto.vectorization_strategy_pb2 import PRICE_ONLY, FULL_ORDER_BOOK
from analyst.price_util import get_price_from_order_book
import numpy as np

L2_ORDER_BOOK_SHAPE = (2, 50, 3)
L2_ORDER_BOOK_PRICE_ONLY_SHAPE = (1,)


def l2_order_book_feature_shape(format):
    if format == FULL_ORDER_BOOK:
        return L2_ORDER_BOOK_SHAPE
    elif format == PRICE_ONLY:
        return L2_ORDER_BOOK_PRICE_ONLY_SHAPE


def vectorize_l2_order_book_frame_component(component: FrameComponent, format):
    return np.asarray([
        vectorize_l2_order_book(d, format) for d in component.data
    ])


def vectorize_l2_order_book(data: DataPoint, format):
    if format == FULL_ORDER_BOOK:
        return np.asarray([
            np.asarray([order_to_vector(o) for o in data.l2_order_book.bids]),
            np.asarray([order_to_vector(o) for o in data.l2_order_book.asks]),
        ])
    elif format == PRICE_ONLY:
        return np.asarray([get_price_from_order_book(data)])


def order_to_vector(order: L2OrderBookEntry):
    return np.asarray([float(x) for x in [order.price, order.size, order.num_orders]])