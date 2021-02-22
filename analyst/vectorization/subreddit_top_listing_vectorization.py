from analyst.proto.vectorization_strategy_pb2 import WEIGHTED_BAG_OF_WORDS, VectorizationStrategy
from analyst.proto.data_point_pb2 import DataPoint
from analyst.proto.frame_component_pb2 import FrameComponent
from analyst.nlp_util import tokenize, normalize, is_stopword
import numpy as np
from collections import Counter

POST_TITLE_BASE_WEIGHT = 50  # Post titles are worth this many comments
MAX_NUMBER_OF_WORDS = 1000


def subreddit_top_listing_feature_shape(format):
    assert format == WEIGHTED_BAG_OF_WORDS
    return (MAX_NUMBER_OF_WORDS, 2)


def vectorize_subreddit_top_listing_frame_component(component: FrameComponent, format):
    return np.asarray([
        vectorize_subreddit_top_listing(d, format) for d in component.data
    ])


def vectorize_subreddit_top_listing(data: DataPoint, format):
    # This is a retarded way to vectorize subreddits. Make a better one, Blake.
    assert format == WEIGHTED_BAG_OF_WORDS
    word_scores = Counter()
    for post in data.subreddit_top_listing.posts:
        for word in tokenize(normalize(post.title)):
            if not is_stopword(word):
                word_scores[word] += POST_TITLE_BASE_WEIGHT
        for comment in post.comments:
            for word in tokenize(normalize(comment.content)):
                if not is_stopword(word):
                    word_scores[word] += 1

    results = word_scores.most_common(MAX_NUMBER_OF_WORDS)
    results.extend([('', 0)] * (MAX_NUMBER_OF_WORDS - len(results)))
    return np.asarray(results)