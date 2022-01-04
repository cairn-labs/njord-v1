from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.frame_config_pb2 import FrameConfig
from analyst.proto.feature_config_pb2 import FeatureConfig
from analyst.proto.frame_component_pb2 import FrameComponent
from analyst.proto.data_point_pb2 import L2_ORDER_BOOK, STONK_AGGREGATE, SUBREDDIT_TOP_LISTING, OPTION_QUOTE, \
    DataPointType, OPTION_QUOTE_CHAIN
from analyst.proto.label_config_pb2 import FX_RATE, STONK_PRICE
from analyst.vectorization.l2_order_book_vectorization import (
    vectorize_l2_order_book_frame_component, l2_order_book_feature_shape)
from analyst.vectorization.fx_rate_label_vectorization import vectorize_fx_rate_label
from analyst.vectorization.stonk_aggregate_vectorization import (
    vectorize_stonk_aggregate_frame_component, stonk_aggregate_feature_shape)
from analyst.vectorization.subreddit_top_listing_vectorization import (
    subreddit_top_listing_feature_shape, vectorize_subreddit_top_listing_frame_component)
from analyst.vectorization.stonk_price_label_vectorization import vectorize_stonk_price_label
from analyst.vectorization.option_quote_vectorization import (
    option_quote_feature_shape, vectorize_option_quote_frame_component
)
from analyst.vectorization.option_quote_chain_vectorization import (
    option_quote_chain_feature_shape, vectorize_option_quote_chain_frame_component
)
import numpy as np


def vectorize_frame(data_frame: DataFrame, frame_config: FrameConfig):
    component_vectors = []
    for idx, component in enumerate(data_frame.components):
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
        label = None
    else:
        label = vectorize_label(data_frame, frame_config)
    return np.asarray(component_vectors), label


def vectorize_component(component: FrameComponent, feature_config: FeatureConfig):
    if component.data_point_type == L2_ORDER_BOOK:
        return (l2_order_book_feature_shape(feature_config.vectorization_strategy),
                vectorize_l2_order_book_frame_component(component, feature_config.vectorization_strategy))
    elif component.data_point_type == STONK_AGGREGATE:
        return (stonk_aggregate_feature_shape(feature_config.vectorization_strategy),
                vectorize_stonk_aggregate_frame_component(component, feature_config.vectorization_strategy))
    elif component.data_point_type == SUBREDDIT_TOP_LISTING:
        return (subreddit_top_listing_feature_shape(feature_config.vectorization_strategy),
                vectorize_subreddit_top_listing_frame_component(component, feature_config.vectorization_strategy))
    elif component.data_point_type == OPTION_QUOTE:
        return (option_quote_feature_shape(feature_config.vectorization_strategy),
                vectorize_option_quote_frame_component(component, feature_config.vectorization_strategy))
    elif component.data_point_type == OPTION_QUOTE_CHAIN:
        return (option_quote_chain_feature_shape(feature_config.vectorization_strategy),
                vectorize_option_quote_chain_frame_component(component, feature_config.vectorization_strategy))
    else:
        raise NotImplementedError(f"Frame component type {DataPointType.Name(component.data_point_type)} not supported.")


def vectorize_label(data_frame: DataFrame, frame_config: FrameConfig):
    if frame_config.label_config.label_type == FX_RATE:
        return vectorize_fx_rate_label(data_frame, frame_config)
    if frame_config.label_config.label_type == STONK_PRICE:
        return vectorize_stonk_price_label(data_frame)


def data_timestamps(data_frame: DataFrame, data_point_type: DataPointType) -> np.ndarray:
    for idx, component in enumerate(data_frame.components):
        if component.data_point_type == data_point_type:
            return np.asarray([d.event_timestamp for d in component.data])