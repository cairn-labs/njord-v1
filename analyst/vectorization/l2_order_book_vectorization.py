from analyst.proto.frame_component_pb2 import FrameComponent
from analyst.proto.l2_order_book_pb2 import L2OrderBookEntry
from analyst.proto.data_point_pb2 import DataPoint
import numpy as np

L2_ORDER_BOOK_SHAPE = (2, 50, 3)


def vectorize_l2_order_book_frame_component(component: FrameComponent):
    return np.asarray([
        vectorize_l2_order_book(d) for d in component.data
    ])


def vectorize_l2_order_book(data: DataPoint):
    return np.asarray([
        np.asarray([order_to_vector(o) for o in data.l2_order_book.bids]),
        np.asarray([order_to_vector(o) for o in data.l2_order_book.asks]),
    ])


def order_to_vector(order: L2OrderBookEntry):
    return np.asarray([float(x) for x in [order.price, order.size, order.num_orders]])