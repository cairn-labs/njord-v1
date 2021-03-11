import os
import glob
from google.protobuf.text_format import Parse
from analyst.proto.frame_config_pb2 import FrameConfig
from analyst.dataset import DataSet
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import OneHotEncoder
from tensorflow.keras import Sequential
from tensorflow.keras.layers import Reshape, LSTM, Dense, Bidirectional, Dropout
import tensorflow as tf
import sys

TRAIN_TEST_SPLIT = 0.75

with open(os.path.join(os.path.dirname(__file__), "stonk_frame_template.pb.txt")) as handle:
    pb_template = handle.read()


def stream_data():
    for filename in glob.glob(os.path.join(os.path.dirname(__file__), "data", "*.zip")):
        stonk, _ = os.path.splitext(os.path.basename(filename))
        if len(sys.argv) > 1 and stonk != sys.argv[1]:
            continue

        frame_config_text = pb_template.replace("{{ticker}}", f'"{stonk}"')
        frame_config = FrameConfig()
        Parse(frame_config_text, frame_config)
        dataset = DataSet(filename, frame_config)
        for X, y in dataset.labeled_data:
            last_X_price = X[0][-1][0]
            if last_X_price == 0:
                continue

            diff = (y - last_X_price)/last_X_price
            if diff > 0.001:
                new_y = 1
            elif diff > -0.001:
                new_y = 0
            else:
                new_y = -1

            yield X, new_y



if __name__ == "__main__":
    X, y = zip(*stream_data())
    X = np.asarray(X)
    y = OneHotEncoder(categories=[[-1, 0, 1]], sparse=False).fit_transform([[d] for d in y])
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=1 - TRAIN_TEST_SPLIT)
    print(X_train.shape)
    print(y_train.shape)
    model = Sequential()
    model.add(Reshape((15, 2), input_shape=(1, 15, 2)))
    model.add(Bidirectional(LSTM(32, return_sequences=True, input_shape=(15, 2), dropout=0.2)))
    model.add(Bidirectional(LSTM(10, input_shape=(15, 2), dropout=0.2)))
    # model.add(Dense(32))
    model.add(Dropout(0.2))
    model.add(Dense(8))
    model.add(Dense(3, activation='softmax'))
    model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
    model.fit(X_train, y_train, epochs=200, batch_size=8, validation_data=(X_test, y_test))
    loss, accuracy = model.evaluate(X_test, y_test)
    print(loss)
    print(accuracy)
    y_true = np.argmax(y_test, axis=1)
    y_pred = np.argmax(model.predict(X_test), axis=1)
    print(tf.math.confusion_matrix(y_true, y_pred))