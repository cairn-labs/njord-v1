import requests
from google.protobuf.text_format import Parse
from analyst.proto.prediction_model_config_pb2 import PredictionModelConfig

import sys

# URL = f'http://trader.tendies.ai/api/get_training_data'
URL = "http://localhost:4000/api/test_predict"

with open(sys.argv[1]) as handle:
    config_text = handle.read()

config = PredictionModelConfig()
Parse(config_text, config)


print('Requesting prediction from server...')
file_upload = {'config': ('config.pb', config.SerializeToString())}
response = requests.post(URL, files=file_upload, allow_redirects=True)
print(response.json())
