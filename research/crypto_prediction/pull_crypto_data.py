import requests
from google.protobuf.text_format import Parse
from analyst.proto.frame_config_pb2 import FrameConfig
import os
import json
import sys

crypto = sys.argv[1]

URL = "http://localhost:4000/api/get_training_data"

with open(os.path.join(os.path.dirname(__file__), "crypto_frame_template.pb.txt")) as handle:
    pb_template = handle.read()


frame_config_text = (pb_template
                     .replace("{{crypto}}", f'{crypto}'))

frame_config = FrameConfig()
Parse(frame_config_text, frame_config)
file_upload = {'frame_config': ('frame_config.pb', frame_config.SerializeToString())}
response = requests.post(URL, files=file_upload, allow_redirects=True)
assert response.status_code == 200, f"Error retrieving training data: {json.loads(response.content)['message']}"

local_dataset = os.path.join(os.path.dirname(__file__), 'data', f'{crypto}.zip')
with open(local_dataset, 'wb') as handle:
    handle.write(response.content)
    print("Wrote", local_dataset)
