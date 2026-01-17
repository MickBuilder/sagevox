#!/bin/bash
# Development server with WebSocket keepalive tuning for long audio streaming

cd "$(dirname "$0")"

echo "Starting SageVox Backend (Development Mode)"
echo "WebSocket ping interval: 60s, timeout: 60s"
echo

uvicorn app.main:app \
  --reload \
  --host 0.0.0.0 \
  --port 8000 \
  --ws-ping-interval 60 \
  --ws-ping-timeout 60
