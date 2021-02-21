import requests
from google.protobuf.text_format import Parse
from analyst.proto.frame_config_pb2 import FrameConfig
from analyst.dataset import DataSet
import os

# All tickers with at least 1000 one minute bars over four days
all_stonks = ["AAL", "AAPL", "ABBV", "ABT", "ACB", "AES", "AFL", "AGNC", "AIKI", "AM", "AMAT", "AMC", "AMD", "APA", "APHA", "AR", "ARKK", "ATUS", "AUY", "AXTA", "AZN", "BA", "BABA", "BAC", "BB", "BBD", "BCRX", "BE", "BIDU", "BKR", "BLDP", "BMY", "BNGO", "BOX", "BP", "BRK.B", "BSX", "C", "CAN", "CCIV", "CCL", "CHGG", "CLF", "CLOV", "CMCSA", "COG", "COP", "COTY", "CRM", "CSCO", "CTXR", "CVS", "CVX", "DAL", "DBX", "DD", "DDOG", "DIS", "DISCA", "DKNG", "DNN", "DUK", "DVN", "EBAY", "EBON", "EEM", "EFA", "EQT", "ET", "EWZ", "F", "FB", "FCEL", "FCX", "FE", "FISV", "FITB", "FOLD", "FSLY", "FTI", "GDX", "GE", "GEVO", "GILD", "GLD", "GM", "GME", "GOLD", "HAL", "HBAN", "HEPA", "HPE", "HPQ", "HST", "HYG", "IBM", "IBN", "IDEX", "INFY", "INO", "INTC", "IQ", "ISBC", "ITUB", "IWM", "JBLU", "JCI", "JD", "JNJ", "JPM", "KEY", "KGC", "KHC", "KMI", "KO", "KR", "LABD", "LI", "LKCO", "LQD", "LUMN", "LUV", "LVS", "LYFT", "M", "MARA", "MDLZ", "MDT", "MET", "MGM", "MOS", "MPC", "MRK", "MRO", "MRVL", "MS", "MSFT", "MU", "NCLH", "NEE", "NEM", "NIO", "NKE", "NLY", "NNDM", "NOK", "NVDA", "NVTA", "NXTD", "ON", "ONTX", "OPEN", "ORCL", "OXY", "PBR", "PEP", "PFE", "PG", "PINS", "PK", "PLTR", "PLUG", "PM", "PTON", "PYPL", "QCOM", "QQQ", "QS", "RCL", "RF", "RIOT", "ROKU", "RRC", "RTX", "RUN", "SABR", "SCHW", "SE", "SENS", "SIRI", "SLB", "SLV", "SNAP", "SNDL", "SO", "SOS", "SPWR", "SPY", "SQ", "SQQQ", "SRNE", "SU", "SWN", "SYF", "T", "TEVA", "TFC", "TJX", "TLRY", "TLT", "TMUS", "TQQQ", "TRCH", "TRIP", "TSLA", "TSM", "TWLO", "TWTR", "UAL", "UBER", "USB", "UVXY", "V", "VALE", "VG", "VIAC", "VLO", "VXX", "VZ", "WBA", "WDC", "WFC", "WMB", "WMT", "X", "XLB", "XLE", "XLF", "XLI", "XLP", "XLU", "XOM", "XPEV", "ZNGA"]

URL = "http://localhost:4000/api/get_training_data"

with open(os.path.join(os.path.dirname(__file__), "stonk_frame_template.pb.txt")) as handle:
    pb_template = handle.read()

for stonk in all_stonks:
    frame_config_text = pb_template.replace("{{ticker}}", f'"{stonk}"')
    frame_config = FrameConfig()
    Parse(frame_config_text, frame_config)
    file_upload = {'frame_config': ('frame_config.pb', frame_config.SerializeToString())}
    response = requests.post(URL, files=file_upload, allow_redirects=True)
    local_dataset = os.path.join(os.path.dirname(__file__), f'{stonk}.zip')
    with open(local_dataset, 'wb') as handle:
        handle.write(response.content)
        print("Wrote", local_dataset)