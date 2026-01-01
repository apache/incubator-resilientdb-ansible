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

# Use Ubuntu 22.04 as the base image
FROM ubuntu:22.04

# Let systemd know we're in a container
ENV container docker
ENV DEBIAN_FRONTEND=noninteractive

# Update apt and install required packages including systemd, ansible, etc.
RUN apt-get update && \
    apt-get install -y gnupg curl systemd ansible sudo git && \
    # Add Bazel's public key
    curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/bazel.gpg && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set up passwordless sudo (container runs as root)
RUN echo "root ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99_nopasswd && \
    chmod 0440 /etc/sudoers.d/99_nopasswd

# Copy the ansible playbook project into the container
COPY . /opt/resilientdb-ansible
WORKDIR /opt/resilientdb-ansible

# Run the ansible playbook non-interactively (passwordless sudo)
RUN ansible-playbook site.yml -i inventories/production/hosts --tags all -e "bazel_jobs=1"

# Fix MemoryDB bug: handle seq=0 as "get latest value" (consistent with LevelDB)
# See: https://github.com/apache/incubator-resilientdb/issues/XXX
RUN sed -i '/if (search_it != kv_map_with_seq_.end() && search_it->second.size()) {/a\    \/\/ When seq is 0, return the latest value (consistent with LevelDB behavior)\n    if (seq == 0) {\n      return search_it->second.back();\n    }' \
    /opt/resilientdb/chain/storage/memory_db.cpp

# Rebuild ResilientDB with the fix
RUN cd /opt/resilientdb && \
    bazel build //service/kv:kv_service //service/tools/kv/api_tools:kv_service_tools

# Fix config files to use JSON format (required by newer ResilientDB)
RUN echo '{"replica_info":[{"id":5,"ip":"127.0.0.1","port":10005}]}' > \
    /opt/ResilientDB-GraphQL/service/tools/config/interface/client.config && \
    echo '{"replica_info":[{"id":1,"ip":"127.0.0.1","port":10001},{"id":2,"ip":"127.0.0.1","port":10002},{"id":3,"ip":"127.0.0.1","port":10003},{"id":4,"ip":"127.0.0.1","port":10004}]}' > \
    /opt/ResilientDB-GraphQL/service/http_server/server_config.config

# Apply the same fix to ResilientDB-GraphQL's cached external dependency and rebuild Crow
# Must use bazel clean to force rebuild after modifying cached external sources
RUN CACHE_FILE=$(find /root/.cache/bazel -name 'memory_db.cpp' -path '*com_resdb_nexres*' 2>/dev/null | head -1) && \
    if [ -n "$CACHE_FILE" ]; then \
        sed -i '/if (search_it != kv_map_with_seq_.end() && search_it->second.size()) {/a\    if (seq == 0) {\n      return search_it->second.back();\n    }' "$CACHE_FILE"; \
    fi && \
    cd /opt/ResilientDB-GraphQL && \
    bazel clean && \
    bazel build //service/http_server:crow_service_main

# Copy the startup scripts and make them executable
COPY startup.sh /opt/resilientdb-ansible/startup.sh
COPY complete-startup.sh /opt/resilientdb-ansible/complete-startup.sh
RUN chmod +x /opt/resilientdb-ansible/startup.sh /opt/resilientdb-ansible/complete-startup.sh

# Copy the startup unit file and enable it
COPY startup-services.service /etc/systemd/system/startup-services.service

# Enable the startup service (so that it runs on boot)
RUN systemctl enable startup-services.service || true

# Expose required ports
EXPOSE 80 18000 8000

# Start systemd as PID1
CMD ["/sbin/init"]
