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
    with open(os.path.join(os.path.dirname(__file__), "pure_technical.pb.txt")) as handle:
        frame_config_text = handle.read()
    frame_config = FrameConfig()
    Parse(frame_config_text, frame_config)
    return frame_config


def stream_data(dataset: DataSet):
    for X, y in dataset.labeled_data:
        stonk = X[0]

        last_stonk_price = stonk[-1][0]
        if last_stonk_price == 0:
            continue
        diff = (y - last_stonk_price) / last_stonk_price
        if diff > 0.003:
            new_y = 1
        elif diff > -0.003:
            new_y = 0
        else:
            new_y = -1

        yield [{'stonk': stonk}, new_y]


if __name__ == '__main__':
    data_filename = sys.argv[1]
    output_model_filename = sys.argv[2]

    frame_config = read_frame_config()
    dataset = DataSet(data_filename, frame_config)

    stonk_input = Input(shape=(8, 2), dtype=tf.float32, name='stonk')
    lstm1 = layers.Bidirectional(layers.LSTM(256, return_sequences=True, input_shape=(8, 2), dropout=0.2))(
        stonk_input)
    lstm2 = layers.Bidirectional(layers.LSTM(128, input_shape=(8, 2), dropout=0.2))(lstm1)
    dense_prices = layers.Dense(32, activation='sigmoid')(lstm2)
    intermediate = layers.Dense(16, activation='sigmoid')(dense_prices)
    direction_pred = layers.Dense(3, name="direction_class", activation='softmax')(intermediate)
    model = Model(
        inputs=[stonk_input],
        outputs=[direction_pred]
    )

    xs, y = zip(*stream_data(dataset))
    y = OneHotEncoder(categories=[[-1, 0, 1]], sparse=False).fit_transform([[d] for d in y])
    xs_train, xs_test, y_train, y_test = train_test_split(xs, y, test_size=1-TRAIN_TEST_SPLIT)
    X_train = {'stonk': np.asarray([x['stonk'] for x in xs_train], dtype=np.float32)}
    X_test = {'stonk': np.asarray([x['stonk'] for x in xs_test], dtype=np.float32)}

    model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    model.fit(
        X_train,
        y_train,
        epochs=250,
        batch_size=1,
        validation_data = (X_test, y_test)
    )

    y_true = np.argmax(y_test, axis=1)
    y_pred = np.argmax(model.predict(X_test), axis=1)
    print(tf.math.confusion_matrix(y_true, y_pred))
    model.save(output_model_filename)