# ResilientDB Ansible Docker Deployment

Run ResilientDB with PBFT consensus using Docker.

## Prerequisites

- Docker installed
- 4GB+ RAM available
- Ports 80, 8000, 18000 free

## Quick Start

### 1. Build

```bash
docker build -t resilientdb-ansible -f dockerfile .
```

### 2. Run

**With systemd (recommended):**
```bash
docker run -d --privileged \
  --name resilientdb-container \
  -p 80:80 -p 8000:8000 -p 18000:18000 \
  resilientdb-ansible
```

**Without systemd:**
```bash
docker run -d \
  --name resilientdb-container \
  -p 80:80 -p 8000:8000 -p 18000:18000 \
  resilientdb-ansible \
  /bin/bash -c "/opt/resilientdb-ansible/complete-startup.sh --foreground"
```

### 3. Test

```bash
# SET
curl -X POST http://localhost:18000/v1/transactions/commit \
  -H "Content-Type: application/json" \
  -d '{"id":"mykey","value":"myvalue"}'

# GET
curl http://localhost:18000/v1/transactions/mykey
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/transactions/commit` | POST | Set key-value (body: `{"id":"key","value":"val"}`) |
| `/v1/transactions/{key}` | GET | Get value by key |

## Architecture

```
Crow HTTP (:18000) → KV Client (:10005) → PBFT Replicas (:10001-10004)
```

- **4 PBFT replicas** (nodes 1-4): Byzantine fault tolerant consensus
- **1 KV client** (node 5): Interface for read/write operations
- **Crow HTTP**: REST API gateway

## Ports

| Port | Service |
|------|---------|
| 18000 | Crow REST API |
| 8000 | GraphQL API |
| 80 | Nginx |

## Troubleshooting

```bash
# Check services
docker exec resilientdb-container pgrep -c kv_service  # Should be 5

# View logs
docker exec resilientdb-container cat /var/log/resilientdb/crow.log

# Restart services
docker exec resilientdb-container /opt/resilientdb-ansible/complete-startup.sh
```

## License

Apache License 2.0
