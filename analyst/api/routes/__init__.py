from fastapi import APIRouter
from analyst.api.routes.prices import router as prices_router


router = APIRouter()
router.include_router(prices_router, prefix="/prices")