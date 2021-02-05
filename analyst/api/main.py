from fastapi import FastAPI
from analyst.api.routes import router
from analyst.config import API_DEBUG_MODE


def get_application() -> FastAPI:
    application = FastAPI(title='Cairn Trading Bot - Analyst', debug=API_DEBUG_MODE)
    application.include_router(router, prefix='/api')
    return application


app = get_application()