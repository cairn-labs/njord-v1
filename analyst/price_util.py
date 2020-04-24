from analyst.proto.data_point_pb2 import DataPoint, L2_ORDER_BOOK


def get_price_from_order_book(data_point: DataPoint):
    assert data_point.data_point_type == L2_ORDER_BOOK
    return (float(data_point.l2_order_book.bids[0].price) +
            float(data_point.l2_order_book.asks[0].price)) / 2
