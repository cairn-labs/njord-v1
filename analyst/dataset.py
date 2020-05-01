import tempfile
import zipfile
import glob
import os
from collections import Counter
import random

from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.frame_config_pb2 import FrameConfig
from analyst.vectorization.frame_vectorization import vectorize_frame


class DataSet:
    def __init__(self, dataset_filename: str, frame_config: FrameConfig):
        self.labeled_data = []
        for frame in self.stream_dataset_frames(dataset_filename):
            input_vector, label = vectorize_frame(frame, frame_config)
            if input_vector is None or label is None:
                continue
            self.labeled_data.append((input_vector, label))
        random.shuffle(self.labeled_data)

    def stream_dataset_frames(self, dataset_filename: str):
        with tempfile.TemporaryDirectory() as temp_dir:
            with zipfile.ZipFile(dataset_filename, 'r') as zip_handle:
                zip_handle.extractall(temp_dir)
                for filename in glob.glob(os.path.join(temp_dir, '*.pb')):
                    with open(filename, 'rb') as pb_handle:
                        frame = DataFrame()
                        frame.ParseFromString(pb_handle.read())
                        yield frame

    def class_counts(self):
        counts = Counter()
        for _, label in self.labeled_data:
            counts[label] += 1
        return dict(counts)