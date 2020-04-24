from analyst.dataset import DataSet


TRAIN_TEST_SPLIT = 0.8


def train_dataset(dataset: DataSet):
    print(dataset.class_counts())