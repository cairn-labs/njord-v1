from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.frame_config_pb2 import FrameConfig
from analyst.proto.data_point_pb2 import L2_ORDER_BOOK
from analyst.price_util import get_price_from_order_book


def vectorize_fx_rate_label(data_frame: DataFrame, frame_config: FrameConfig):
    label_price = float(data_frame.label.value_decimal)
    if not frame_config.label_config.fx_rate_config.label_direction_only:
        return label_price

    final_input_price = get_final_input_price(data_frame)
    if final_input_price is None:
        return None

    if label_price >= ((1 + frame_config.label_config.fx_rate_config.movement_minimum_percent_change)
                       * final_input_price):
        return 1
    elif label_price > ((1 - frame_config.label_config.fx_rate_config.movement_minimum_percent_change)
                        * final_input_price):
        return 0
    else:
        return -1



def get_final_input_price(data_frame: DataFrame):
    for component in data_frame.components:
        if component.data_point_type == L2_ORDER_BOOK:
            return get_price_from_order_book(component.data[-1])
    return None
