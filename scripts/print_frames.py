import sys
import tempfile
import zipfile
import glob
import os

from google.protobuf.text_format import Parse
from analyst.proto.data_frame_pb2 import DataFrame
from analyst.proto.frame_config_pb2 import FrameConfig
from analyst.vectorization.frame_vectorization import vectorize_frame

with open(sys.argv[2]) as handle:
    frame_config_text = handle.read()

frame_config = FrameConfig()
Parse(frame_config_text, frame_config)

with tempfile.TemporaryDirectory() as temp_dir:
    with zipfile.ZipFile(sys.argv[1], 'r') as zip_handle:
        zip_handle.extractall(temp_dir)
        for filename in glob.glob(os.path.join(temp_dir, '*.pb')):
            with open(filename, 'rb') as pb_handle:
                frame = DataFrame()
                frame.ParseFromString(pb_handle.read())
                print(vectorize_frame(frame, frame_config))
