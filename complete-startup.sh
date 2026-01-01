#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# Complete startup script for ResilientDB services
# Use this when running the container without systemd

set -e

LOG_DIR="/var/log/resilientdb"
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

wait_for_port() {
    local port=$1
    local timeout=${2:-30}
    local start_time=$(date +%s)

    while ! ss -tlnp | grep -q ":${port}"; do
        if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
            log "ERROR: Timeout waiting for port $port"
            return 1
        fi
        sleep 0.5
    done
    return 0
}

log "=== ResilientDB Complete Startup Script ==="

# Kill all existing services
log "Stopping existing services..."
pkill -9 -f kv_service 2>/dev/null || true
pkill -9 -f crow_service_main 2>/dev/null || true
pkill -9 -f gunicorn 2>/dev/null || true
pkill -f nginx 2>/dev/null || true
sleep 2

# Start nginx
log "Starting nginx..."
nginx
log "Nginx started"

# Start ResilientDB KV replicas (nodes 1-4)
# PBFT requires 3f+1 nodes, where f=1, so we need 4 replicas
log "Starting PBFT replicas..."

for i in 1 2 3 4; do
    /opt/resilientdb/bazel-bin/service/kv/kv_service \
        /opt/resilientdb/service/tools/config/server/server.config \
        /opt/resilientdb/service/tools/data/cert/node${i}.key.pri \
        /opt/resilientdb/service/tools/data/cert/cert_${i}.cert \
        > "$LOG_DIR/node${i}.log" 2>&1 &
    log "  Node $i (replica) started - PID $!"
done

# Wait for replicas to be ready
log "Waiting for replicas to initialize..."
sleep 3

for port in 10001 10002 10003 10004; do
    if wait_for_port $port 10; then
        log "  Port $port is ready"
    else
        log "  WARNING: Port $port not responding"
    fi
done

# Start ResilientDB Client (node 5)
log "Starting KV client (node 5)..."
/opt/resilientdb/bazel-bin/service/kv/kv_service \
    /opt/resilientdb/service/tools/config/server/server.config \
    /opt/resilientdb/service/tools/data/cert/node5.key.pri \
    /opt/resilientdb/service/tools/data/cert/cert_5.cert \
    > "$LOG_DIR/node5.log" 2>&1 &
log "  Node 5 (client) started - PID $!"

if wait_for_port 10005 10; then
    log "  Port 10005 is ready"
else
    log "  WARNING: Port 10005 not responding"
fi

# Start Crow HTTP service
log "Starting Crow HTTP service..."
cd /opt/ResilientDB-GraphQL
./bazel-bin/service/http_server/crow_service_main \
    service/tools/config/interface/client.config \
    service/http_server/server_config.config \
    > "$LOG_DIR/crow.log" 2>&1 &
log "  Crow HTTP started - PID $!"

if wait_for_port 18000 10; then
    log "  Port 18000 is ready"
else
    log "  WARNING: Port 18000 not responding"
fi

# Start GraphQL service (optional)
log "Starting GraphQL service..."
cd /opt/ResilientDB-GraphQL
export PATH="/opt/ResilientDB-GraphQL/venv/bin:$PATH"
if [ -f "/opt/ResilientDB-GraphQL/app.py" ]; then
    /usr/bin/gunicorn -w 4 -b 0.0.0.0:8000 \
        --pythonpath /opt/ResilientDB-GraphQL/venv/lib/python3.10/site-packages \
        --timeout 120 \
        app:app \
        > "$LOG_DIR/graphql.log" 2>&1 &
    log "  GraphQL started - PID $!"
else
    log "  GraphQL app.py not found, skipping"
fi

# Final status check
log ""
log "=== Service Status ==="
sleep 2

log "Running processes:"
pgrep -a kv_service | while read line; do log "  $line"; done
pgrep -a crow_service | while read line; do log "  $line"; done
pgrep -a gunicorn | head -1 | while read line; do log "  $line"; done

log ""
log "Listening ports:"
ss -tlnp | grep -E ":(80|8000|18000|1000[1-5])" | while read line; do log "  $line"; done

log ""
log "=== Startup Complete ==="
log "Logs available in: $LOG_DIR"
log ""
log "API Endpoints:"
log "  Crow HTTP API: http://localhost:18000/v1/transactions/"
log "  GraphQL API:   http://localhost:8000/graphql"
log ""

# Keep running if called directly (for docker exec)
if [ "${1:-}" = "--foreground" ]; then
    log "Running in foreground mode. Press Ctrl+C to exit."
    tail -f /dev/null
fi
