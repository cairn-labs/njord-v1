import sys
import os
import csv
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


TRAIN_TEST_SPLIT = 0.85

def encode_weighted_words(weighted_words, dictionary: WordDictionary):
    return np.asarray([[dictionary.learn_and_encode(word), score] for word, score in weighted_words], dtype=int)


def read_frame_config(crypto):
    with open(os.path.join(os.path.dirname(__file__), "crypto_frame_template.pb.txt")) as handle:
        frame_config_text = (handle
                             .read()
                             .replace("{{crypto}}", f'{crypto}'))

    frame_config = FrameConfig()
    Parse(frame_config_text, frame_config)
    return frame_config


def stream_data(dataset: DataSet, frame_config: FrameConfig, dictionary: WordDictionary):
    for X, y in dataset.labeled_data:
        crypto, reddit1, reddit2, reddit3 = X
        reddit1 = encode_weighted_words(reddit1[0], dictionary)
        reddit2 = encode_weighted_words(reddit2[0], dictionary)
        reddit3 = encode_weighted_words(reddit3[0], dictionary)
        yield [{'crypto': crypto, 'reddit1': reddit1, 'reddit2': reddit2, 'reddit3': reddit3}, y]


if __name__ == '__main__':
    crypto = sys.argv[1]
    data_filename = os.path.join(os.path.dirname(__file__), 'data', f'{crypto}.zip')

    frame_config = read_frame_config(crypto)
    dataset = DataSet(data_filename, frame_config)
    dictionary = WordDictionary()

    crypto_input = Input(shape=(120,), dtype=tf.float32, name='crypto')
    crypto_reshaped = layers.Reshape(target_shape=(120, 1))(crypto_input)

    lstm1 = layers.Bidirectional(layers.LSTM(64, return_sequences=True, input_shape=(120, 1), dropout=0.2))(crypto_reshaped)
    lstm2 = layers.Bidirectional(layers.LSTM(32, input_shape=(120, 1), dropout=0.2))(lstm1)

    dense_prices = layers.Dense(32, activation='sigmoid')(lstm2)

    reddit1_input = Input(shape=(1000, 2), dtype=tf.float32, name='reddit1')
    reddit1_reshaped = layers.Reshape((2000,))(reddit1_input)
    dense_reddit1 = layers.Dense(128, activation='sigmoid')(reddit1_reshaped)

    reddit2_input = Input(shape=(1000, 2), dtype=tf.float32, name='reddit2')
    reddit2_reshaped = layers.Reshape((2000,))(reddit2_input)
    dense_reddit2 = layers.Dense(128, activation='sigmoid')(reddit2_reshaped)

    reddit3_input = Input(shape=(1000, 2), dtype=tf.float32, name='reddit3')
    reddit3_reshaped = layers.Reshape((2000,))(reddit3_input)
    dense_reddit3 = layers.Dense(128, activation='sigmoid')(reddit3_reshaped)

    x = layers.concatenate([dense_prices, dense_reddit1, dense_reddit2, dense_reddit3])
    intermediate = layers.Dense(128, activation='sigmoid')(x)
    intermediate2 = layers.Dense(64, activation='sigmoid')(intermediate)
    direction_pred = layers.Dense(3, name="direction_class", activation='softmax')(intermediate2)
    model = Model(
        inputs=[crypto_input, reddit1_input, reddit2_input, reddit3_input],
        outputs=[direction_pred]
    )

    xs, y = zip(*stream_data(dataset, frame_config, dictionary))

    y = OneHotEncoder(categories=[[-1, 0, 1]], sparse=False).fit_transform([[d] for d in y])
    xs_train, xs_test, y_train, y_test = train_test_split(xs, y, test_size=1 - TRAIN_TEST_SPLIT)
    X_train = {'crypto': np.asarray([x['crypto'] for x in xs_train], dtype=np.float32),
               'reddit1': np.asarray([x['reddit1'] for x in xs_train], dtype=np.float32),
               'reddit2': np.asarray([x['reddit2'] for x in xs_train], dtype=np.float32),
               'reddit3': np.asarray([x['reddit3'] for x in xs_train], dtype=np.float32)}
    X_test = {'crypto': np.asarray([x['crypto'] for x in xs_test], dtype=np.float32),
              'reddit1': np.asarray([x['reddit1'] for x in xs_test], dtype=np.float32),
              'reddit2': np.asarray([x['reddit2'] for x in xs_test], dtype=np.float32),
              'reddit3': np.asarray([x['reddit3'] for x in xs_test], dtype=np.float32)}

    model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    model.fit(
        X_train,
        y_train,
        epochs=40,
        batch_size=2
    )

    y_true = np.argmax(y_test, axis=1)
    y_pred = np.argmax(model.predict(X_test), axis=1)
    confusion_matrix = tf.math.confusion_matrix(y_true, y_pred)

    up_precision = float(confusion_matrix[2][2] / np.sum(confusion_matrix, axis=0)[2])
    up_recall = float(confusion_matrix[2][2] / np.sum(confusion_matrix, axis=1)[2])
    down_precision = float(confusion_matrix[0][0] / np.sum(confusion_matrix, axis=0)[0])
    down_recall = float(confusion_matrix[0][0] / np.sum(confusion_matrix, axis=1)[0])

    print(confusion_matrix)
    print('up precision:', up_precision)
    print('up recall:', up_recall)
    print('down precision:', down_precision)
    print('down recall:', down_recall)