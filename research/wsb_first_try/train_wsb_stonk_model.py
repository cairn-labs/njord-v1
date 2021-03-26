import sys
import os
from google.protobuf.text_format import Parse
from analyst.proto.frame_config_pb2 import FrameConfig
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

# https://github.com/tensorflow/tensorflow/issues/36508
physical_devices = tf.config.list_physical_devices('GPU')
for device in physical_devices:
    tf.config.experimental.set_memory_growth(device, enable=True)


def read_frame_config():
    with open(os.path.join(os.path.dirname(__file__), "gme_and_wsb.pb.txt")) as handle:
        frame_config_text = handle.read()
    frame_config = FrameConfig()
    Parse(frame_config_text, frame_config)
    return frame_config


def encode_weighted_words(weighted_words, dictionary: WordDictionary):
    return np.asarray([[dictionary.learn_and_encode(word), score] for word, score in weighted_words], dtype=int)


def stream_data(dataset: DataSet, dictionary: WordDictionary):
    for X, y in dataset.labeled_data:
        gme, wsb = X

        last_gme_price = gme[-1][0]
        if last_gme_price == 0:
            continue
        diff = (y - last_gme_price) / last_gme_price
        if diff > 0.005:
            new_y = 1
        elif diff > -0.005:
            new_y = 0
        else:
            new_y = -1

        wsb = encode_weighted_words(wsb[0], dictionary)


        yield [{'gme': gme, 'wsb': wsb}, new_y]


if __name__ == '__main__':
    data_filename = sys.argv[1]
    output_model_filename = sys.argv[2]

    frame_config = read_frame_config()
    dataset = DataSet(data_filename, frame_config)
    dictionary = WordDictionary()

    gme_input = Input(shape=(8, 2), dtype=tf.float32, name='gme')
    lstm1 = layers.Bidirectional(layers.LSTM(64, return_sequences=True, input_shape=(8, 2), dropout=0.2))(
        gme_input)
    lstm2 = layers.Bidirectional(layers.LSTM(32, input_shape=(8, 2), dropout=0.2))(lstm1)
    dense_prices = layers.Dense(32, activation='sigmoid')(lstm2)

    # wsb_input = Input(shape=(1000, 2), dtype=tf.float32, name='wsb')
    # wsb_reshaped = layers.Reshape((2000,))(wsb_input)
    # dense_wsb = layers.Dense(128, activation='sigmoid')(wsb_reshaped)
    # x = layers.concatenate([dense_prices, dense_wsb])
    intermediate = layers.Dense(16, activation='sigmoid')(dense_prices)
    direction_pred = layers.Dense(3, name="direction_class", activation='softmax')(intermediate)
    model = Model(
        inputs=[gme_input], #, wsb_input],
        outputs=[direction_pred]
    )

    xs, y = zip(*stream_data(dataset, dictionary))
    y = OneHotEncoder(categories=[[-1, 0, 1]], sparse=False).fit_transform([[d] for d in y])
    xs_train, xs_test, y_train, y_test = train_test_split(xs, y, test_size=1 - TRAIN_TEST_SPLIT)
    X_train = {'gme': np.asarray([x['gme'] for x in xs_train], dtype=np.float32),
               'wsb': np.asarray([x['wsb'] for x in xs_train], dtype=np.float32)}
    X_test = {'gme': np.asarray([x['gme'] for x in xs_test], dtype=np.float32),
               'wsb': np.asarray([x['wsb'] for x in xs_test], dtype=np.float32)}
    print(xs_train, y_train)
    model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    model.fit(
        X_train,
        y_train,
        epochs=500,
        batch_size=4,
        validation_data = (X_test, y_test)
    )

    y_true = np.argmax(y_test, axis=1)
    y_pred = np.argmax(model.predict(X_test), axis=1)
    print(tf.math.confusion_matrix(y_true, y_pred))
    model.save(output_model_filename)