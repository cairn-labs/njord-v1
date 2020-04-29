import requests
from google.protobuf.text_format import Parse
from analyst.proto.frame_config_pb2 import FrameConfig
from analyst.dataset import DataSet
from analyst.training import train_dataset
import sys

URL = f'http://gpu:4000/api/get_training_data'
LOCAL_DATASET_LOCATION = '/tmp/frames.zip'

with open(sys.argv[1]) as handle:
    frame_config_text = handle.read()

print('Requesting training data from server...')
frame_config = FrameConfig()
Parse(frame_config_text, frame_config)
file_upload = {'frame_config': ('frame_config.pb', frame_config.SerializeToString())}
response = requests.post(URL, files=file_upload, allow_redirects=True)
with open(LOCAL_DATASET_LOCATION, 'wb') as handle:
    handle.write(response.content)

print('Vectorizing training data...')
dataset = DataSet(LOCAL_DATASET_LOCATION, frame_config)

print('Starting training...')
train_dataset(dataset)
