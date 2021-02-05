#!/bin/bash
set -e

source venv/bin/activate
pip install -r requirements.txt
uvicorn analyst.api.main:app --reload --port 8001
