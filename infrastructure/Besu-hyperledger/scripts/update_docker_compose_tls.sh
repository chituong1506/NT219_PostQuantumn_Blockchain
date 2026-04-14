#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Update docker-compose.yml to mount TLS certificates
# This script adds TLS volume mounts to all Besu nodes
# ============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_COMPOSE="$BASE_DIR/docker-compose.yml"
DOCKER_COMPOSE_BACKUP="$BASE_DIR/docker-compose.yml.backup-$(date +%Y%m%d-%H%M%S)"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Backup original docker-compose.yml
log_info "Creating backup: $DOCKER_COMPOSE_BACKUP"
cp "$DOCKER_COMPOSE" "$DOCKER_COMPOSE_BACKUP"

log_info "Docker-compose.yml backed up successfully"
log_info "TLS certificates are already generated in config/tls/"
log_info ""
log_warn "IMPORTANT: You need to manually update docker-compose.yml for each node"
log_warn "Add the following volume mount to each Besu service:"
log_warn ""
echo "    volumes:"
echo "      - ./config/besu/:/config"
echo "      - ./config/nodes/<NODE_NAME>:/opt/besu/keys"
echo "      - ./config/tls:/config/tls:ro  # <-- ADD THIS LINE"
echo "      - ./logs/besu:/tmp/besu"
log_warn ""
log_info "Then update the entrypoint to replace NODE_NAME in config.toml:"
log_info ""
echo '      sed -i "s/NODE_NAME/<actual_node_name>/g" /config/config.toml'
log_info ""
log_info "Backup saved at: $DOCKER_COMPOSE_BACKUP"

