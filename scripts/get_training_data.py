import requests
from google.protobuf.text_format import Parse
from analyst.proto.frame_config_pb2 import FrameConfig
import sys

num_requested = sys.argv[2]

URL = f'http://localhost:4000/api/get_training_data/{num_requested}'
with open(sys.argv[1]) as handle:
    frame_config_text = handle.read()

frame_config = FrameConfig()
Parse(frame_config_text, frame_config)
file_upload = {'frame_config': ('frame_config.pb', frame_config.SerializeToString())}
response = requests.post(URL, files=file_upload, allow_redirects=True)
with open('frames.zip', 'wb') as handle:
    handle.write(response.content)
