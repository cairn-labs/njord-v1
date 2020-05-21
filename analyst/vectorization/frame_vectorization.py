from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.frame_config_pb2 import FrameConfig
from analyst.proto.feature_config_pb2 import FeatureConfig
from analyst.proto.frame_component_pb2 import FrameComponent
from analyst.proto.vectorization_strategy_pb2 import FULL_ORDER_BOOK, PRICE_ONLY
from analyst.proto.data_point_pb2 import L2_ORDER_BOOK
from analyst.proto.label_config_pb2 import FX_RATE
from analyst.vectorization.l2_order_book_vectorization import (
    vectorize_l2_order_book_frame_component, l2_order_book_feature_shape)
from analyst.vectorization.fx_rate_label_vectorization import vectorize_fx_rate_label
import numpy as np

DEBUG_EVENT_TIMESTAMPS = False


def vectorize_frame(data_frame: DataFrame, frame_config: FrameConfig):
    component_vectors = []
    prev_time = 0
    for idx, component in enumerate(data_frame.components):
        if DEBUG_EVENT_TIMESTAMPS:
            print()
            for d in component.data:
                ts = d.event_timestamp // 1000
                print(ts, ts - prev_time if prev_time > 0 else "")
                prev_time = ts

        num_buckets = (frame_config.frame_width_ms
                       // frame_config.feature_configs[idx].bucket_width_ms)
        target_feature_shape, arr = vectorize_component(component, frame_config.feature_configs[idx])
        target_frame_shape = (num_buckets,) + target_feature_shape
        if arr.shape != target_frame_shape:
            print(f'Error vectorizing component {idx} of frame: expecting shape '
                  f'{target_frame_shape} but got {arr.shape}. Skipping frame.')
            return None, None
        component_vectors.append(arr)

    if not data_frame.HasField('label'):
        print('Error parsing frame: no label. Skipping frame.')
        return None, None

    if DEBUG_EVENT_TIMESTAMPS:
        ts = data_frame.label.event_timestamp // 1000
        print('label:', ts, ts - prev_time if prev_time > 0 else "")

    label = vectorize_label(data_frame, frame_config)
    return np.asarray(component_vectors), label


def vectorize_component(component: FrameComponent, feature_config: FeatureConfig):
    if component.data_point_type == L2_ORDER_BOOK:
        return (l2_order_book_feature_shape(feature_config.vectorization_strategy),
                vectorize_l2_order_book_frame_component(component, feature_config.vectorization_strategy))


def vectorize_label(data_frame: DataFrame, frame_config: FrameConfig):
    if frame_config.label_config.label_type == FX_RATE:
        return vectorize_fx_rate_label(data_frame, frame_config)
