from analyst.dataset import DataSet
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import OneHotEncoder
from tensorflow.keras import Sequential
from tensorflow.keras.layers import Reshape, LSTM, Dense, Bidirectional
from tensorflow.keras.losses import categorical_crossentropy

TRAIN_TEST_SPLIT = 0.8


def train_dataset(dataset: DataSet):
    X, y = zip(*dataset.labeled_data)
    X = np.asarray(X)
    y = OneHotEncoder(categories=[[-1, 0, 1]], sparse=False).fit_transform([[d] for d in y])
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=1-TRAIN_TEST_SPLIT)
    print(X_train.shape)
    print(y_train.shape)
    model = Sequential()
    model.add(Reshape((15, 1), input_shape=(1, 15, 1)))
    model.add(Bidirectional(LSTM(200, return_sequences=True, input_shape=(15, 1))))
    model.add(Bidirectional(LSTM(200)))
    model.add(Dense(100))
    model.add(Dense(50))
    model.add(Dense(3, activation='softmax'))
    model.compile(optimizer='rmsprop', loss='categorical_crossentropy', metrics=['accuracy'])
    model.fit(X_train, y_train, epochs=150, batch_size=32)
    loss, accuracy = model.evaluate(X_test, y_test)
    print(loss)
    print(accuracy)

