#!/bin/bash
echo "Killing existing processes..."

# Kill all existing services using pkill
pkill -f kv_service 2>/dev/null || true
pkill -f nginx 2>/dev/null || true
pkill -f crow_service_main 2>/dev/null || true
pkill -f crow-http 2>/dev/null || true
pkill -f gunicorn 2>/dev/null || true
pkill -f graphql 2>/dev/null || true

echo "Starting services fresh..."

# Start nginx
nginx &
echo "Nginx started"

# Start ResilientDB KV services (nodes 1-4)
/opt/resilientdb/bazel-bin/service/kv/kv_service /opt/resilientdb/service/tools/config/server/server.config /opt/resilientdb/service/tools/data/cert/node1.key.pri /opt/resilientdb/service/tools/data/cert/cert_1.cert &
echo "ResilientDB KV Node 1 started"

/opt/resilientdb/bazel-bin/service/kv/kv_service /opt/resilientdb/service/tools/config/server/server.config /opt/resilientdb/service/tools/data/cert/node2.key.pri /opt/resilientdb/service/tools/data/cert/cert_2.cert &
echo "ResilientDB KV Node 2 started"

/opt/resilientdb/bazel-bin/service/kv/kv_service /opt/resilientdb/service/tools/config/server/server.config /opt/resilientdb/service/tools/data/cert/node3.key.pri /opt/resilientdb/service/tools/data/cert/cert_3.cert &
echo "ResilientDB KV Node 3 started"

/opt/resilientdb/bazel-bin/service/kv/kv_service /opt/resilientdb/service/tools/config/server/server.config /opt/resilientdb/service/tools/data/cert/node4.key.pri /opt/resilientdb/service/tools/data/cert/cert_4.cert &
echo "ResilientDB KV Node 4 started"

# Start ResilientDB Client (node 5)
/opt/resilientdb/bazel-bin/service/kv/kv_service /opt/resilientdb/service/tools/config/server/server.config /opt/resilientdb/service/tools/data/cert/node5.key.pri /opt/resilientdb/service/tools/data/cert/cert_5.cert &
echo "ResilientDB Client (Node 5) started"

# Start Crow HTTP service
cd /opt/ResilientDB-GraphQL
/opt/ResilientDB-GraphQL/bazel-bin/service/http_server/crow_service_main service/tools/config/interface/client.config service/http_server/server_config.config &
echo "Crow HTTP service started"

# Start GraphQL service
cd /opt/ResilientDB-GraphQL
export PATH="/opt/ResilientDB-GraphQL/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
/usr/bin/gunicorn -w 10 -b 0.0.0.0:8000 --pythonpath /opt/ResilientDB-GraphQL/venv/lib/python3.10/site-packages --timeout 120 app:app &
echo "GraphQL service started"

echo "All services started. Checking status..."
sleep 10
ps aux | grep -E "(kv_service|nginx|crow|gunicorn)"

# Check if all required ports are listening
echo "Checking ports..."
netstat -tlnp | grep -E ":(80|8000|18000|10001|10002|10003|10004|10005)"

# Keep the script running
tail -f /dev/null