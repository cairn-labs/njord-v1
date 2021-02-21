from analyst.proto.data_frame_pb2 import DataFrame


def vectorize_stonk_price_label(data_frame: DataFrame):
    return float(data_frame.label.value_decimal)