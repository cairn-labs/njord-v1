import os
from analyst.config.shared import *

ENV = os.getenv("DATALAKE_ENV", "dev_local")
if ENV == "dev_local":
    from analyst.config.dev_local import *