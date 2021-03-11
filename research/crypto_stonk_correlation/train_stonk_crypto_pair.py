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


def read_frame_config(stonk, crypto):
    with open(os.path.join(os.path.dirname(__file__), "stonk_and_crypto_frame_template.pb.txt")) as handle:
        frame_config_text = (handle
                             .read()
                             .replace("{{ticker}}", f'"{stonk}"')
                             .replace("{{crypto}}", f'{crypto}'))

    frame_config = FrameConfig()
    Parse(frame_config_text, frame_config)
    return frame_config


def stream_data(dataset: DataSet):
    for X, y in dataset.labeled_data:
        stonk, crypto = X

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

        yield [{'stonk': stonk, 'crypto': crypto}, new_y]


if __name__ == '__main__':
    stonk = sys.argv[1]
    crypto = sys.argv[2]
    data_filename = os.path.join(os.path.dirname(__file__), 'data', f'{stonk}-{crypto}.zip')

    frame_config = read_frame_config(stonk, crypto)
    dataset = DataSet(data_filename, frame_config)
    dictionary = WordDictionary()

    stonk_input = Input(shape=(120, 2), dtype=tf.float32, name='stonk')
    stonk_lstm1 = layers.Bidirectional(layers.LSTM(32, return_sequences=True, input_shape=(120, 2), dropout=0.2))(stonk_input)
    stonk_lstm2 = layers.Bidirectional(layers.LSTM(10, input_shape=(15, 2), dropout=0.2))(stonk_lstm1)
    dense_stonk = layers.Dense(8)(stonk_lstm2)

    crypto_input = Input(shape=(480,), dtype=tf.float32, name='crypto')
    crypto_reshaped = layers.Reshape(target_shape=(480,1))(crypto_input)
    crypto_lstm1 = layers.Bidirectional(layers.LSTM(32, return_sequences=True, input_shape=(480,1), dropout=0.2))(crypto_reshaped)
    crypto_lstm2 = layers.Bidirectional(layers.LSTM(10, input_shape=(480,1), dropout=0.2))(crypto_lstm1)

    dense_crypto = layers.Dense(16)(crypto_lstm2)

    x = layers.concatenate([dense_stonk, dense_crypto])
    intermediate = layers.Dense(16)(x)
    direction_pred = layers.Dense(3, name="direction_class")(intermediate)
    model = Model(
        inputs=[stonk_input, crypto_input],
        outputs=[direction_pred]
    )

    xs, y = zip(*stream_data(dataset))

    y = OneHotEncoder(categories=[[-1, 0, 1]], sparse=False).fit_transform([[d] for d in y])
    xs_train, xs_test, y_train, y_test = train_test_split(xs, y, test_size=1 - TRAIN_TEST_SPLIT)
    X_train = {'stonk': np.asarray([x['stonk'] for x in xs_train], dtype=np.float32),
               'crypto': np.asarray([x['crypto'] for x in xs_train], dtype=np.float32)}
    X_test = {'stonk': np.asarray([x['stonk'] for x in xs_test], dtype=np.float32),
              'crypto': np.asarray([x['crypto'] for x in xs_test], dtype=np.float32)}
    print(xs_train, y_train)
    model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    model.fit(
        X_train,
        y_train,
        epochs=50,
        batch_size=1
    )

    y_true = np.argmax(y_test, axis=1)
    y_pred = np.argmax(model.predict(X_test), axis=1)
    print(tf.math.confusion_matrix(y_true, y_pred))