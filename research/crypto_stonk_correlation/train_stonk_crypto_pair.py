import sys
import os
from google.protobuf.text_format import Parse
from analyst.proto.frame_config_pb2 import FrameConfig
from analyst.proto.label_config_pb2 import LabelType
from analyst.dataset import DataSet
from analyst.word_dictionary import WordDictionary
import numpy as np

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import OneHotEncoder
from tensorflow.keras import Input
from tensorflow.keras import layers
from tensorflow.keras.models import Model
import tensorflow as tf


TRAIN_TEST_SPLIT = 0.8

def encode_weighted_words(weighted_words, dictionary: WordDictionary):
    return np.asarray([[dictionary.learn_and_encode(word), score] for word, score in weighted_words], dtype=int)


def read_frame_config(stonk, crypto):
    with open(os.path.join(os.path.dirname(__file__), "stonk_and_crypto_frame_template.pb.txt")) as handle:
        frame_config_text = (handle
                             .read()
                             .replace("{{ticker}}", f'"{stonk}"')
                             .replace("{{crypto}}", f'{crypto}'))

    frame_config = FrameConfig()
    Parse(frame_config_text, frame_config)
    return frame_config


def stream_data(dataset: DataSet, frame_config: FrameConfig, dictionary: WordDictionary):
    for X, y in dataset.labeled_data:
        stonk, crypto, reddit = X

        if frame_config.label_config.label_type == LabelType.STONK_PRICE:
            last_stonk_price = stonk[-1][0]
            if last_stonk_price == 0:
                continue
            diff = (y - last_stonk_price) / last_stonk_price
            if diff > 0.002:
                new_y = 1
            elif diff > -0.002:
                new_y = 0
            else:
                new_y = -1
        elif frame_config.label_config.label_type == LabelType.FX_RATE:
            new_y = y
        else:
            raise ValueError()

        reddit = encode_weighted_words(reddit[0], dictionary)

        yield [{'stonk': stonk, 'crypto': crypto, 'reddit': reddit}, new_y]


if __name__ == '__main__':
    stonk = sys.argv[1]
    crypto = sys.argv[2]
    data_filename = os.path.join(os.path.dirname(__file__), 'data', f'{stonk}-{crypto}.zip')

    frame_config = read_frame_config(stonk, crypto)
    dataset = DataSet(data_filename, frame_config)
    dictionary = WordDictionary()

    stonk_input = Input(shape=(60, 2), dtype=tf.float32, name='stonk')
    upsampled = layers.UpSampling1D(size=4)(stonk_input)
    crypto_input = Input(shape=(240,), dtype=tf.float32, name='crypto')
    crypto_reshaped = layers.Reshape(target_shape=(240, 1))(crypto_input)
    concatenated = layers.concatenate([upsampled, crypto_reshaped], axis=2)

    lstm1 = layers.Bidirectional(layers.LSTM(512, return_sequences=True, input_shape=(240, 3), dropout=0.2))(concatenated)
    lstm2 = layers.Bidirectional(layers.LSTM(256, input_shape=(240, 3), dropout=0.2))(lstm1)

    dense_prices = layers.Dense(128, activation='sigmoid')(lstm2)

    reddit_input = Input(shape=(1000, 2), dtype=tf.float32, name='reddit')
    reddit_reshaped = layers.Reshape((2000,))(reddit_input)
    dense_reddit = layers.Dense(128, activation='sigmoid')(reddit_reshaped)

    x = layers.concatenate([dense_prices, dense_reddit])
    intermediate = layers.Dense(128, activation='sigmoid')(x)
    intermediate2 = layers.Dense(64, activation='sigmoid')(intermediate)
    direction_pred = layers.Dense(3, name="direction_class", activation='softmax')(intermediate2)
    model = Model(
        inputs=[stonk_input, crypto_input, reddit_input],
        outputs=[direction_pred]
    )

    xs, y = zip(*stream_data(dataset, frame_config, dictionary))

    y = OneHotEncoder(categories=[[-1, 0, 1]], sparse=False).fit_transform([[d] for d in y])
    xs_train, xs_test, y_train, y_test = train_test_split(xs, y, test_size=1 - TRAIN_TEST_SPLIT)
    X_train = {'stonk': np.asarray([x['stonk'] for x in xs_train], dtype=np.float32),
               'crypto': np.asarray([x['crypto'] for x in xs_train], dtype=np.float32),
               'reddit': np.asarray([x['reddit'] for x in xs_train], dtype=np.float32)}
    X_test = {'stonk': np.asarray([x['stonk'] for x in xs_test], dtype=np.float32),
              'crypto': np.asarray([x['crypto'] for x in xs_test], dtype=np.float32),
              'reddit': np.asarray([x['reddit'] for x in xs_test], dtype=np.float32)}
    print(y_train)
    model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    model.fit(
        X_train,
        y_train,
        epochs=30,
        batch_size=1
    )

    y_true = np.argmax(y_test, axis=1)
    y_pred = np.argmax(model.predict(X_test), axis=1)
    print(tf.math.confusion_matrix(y_true, y_pred))