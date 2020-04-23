import sys
import tempfile
import zipfile
import glob
import os

from analyst.proto.data_frame_pb2 import DataFrame

with tempfile.TemporaryDirectory() as temp_dir:
    with zipfile.ZipFile(sys.argv[1], 'r') as zip_handle:
        zip_handle.extractall(temp_dir)
        for filename in glob.glob(os.path.join(temp_dir, '*.pb')):
            with open(filename, 'rb') as pb_handle:
                frame = DataFrame()
                frame.ParseFromString(pb_handle.read())
                print(frame.label)
