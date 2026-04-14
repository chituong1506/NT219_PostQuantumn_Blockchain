#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Generate individual config.toml for each node with TLS settings
# ============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$BASE_DIR/config/besu"
NODES_DIR="$BASE_DIR/config/nodes"

# Color output
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# List of all nodes
NODES=(sbv vietcombank vietinbank bidv rpcnode member1besu member2besu member3besu)

log_info "Generating individual config.toml for each node..."

for node in "${NODES[@]}"; do
    log_info "Creating config for: $node"
    
    # Create node-specific config directory if not exists
    mkdir -p "$NODES_DIR/$node"
    
    # Copy base config and replace NODE_NAME with actual node name
    sed "s/NODE_NAME/$node/g" "$CONFIG_DIR/config.toml" > "$NODES_DIR/$node/config-tls.toml"
    
    log_info "  ✓ Created: $NODES_DIR/$node/config-tls.toml"
done

log_info ""
log_info "All node-specific configurations created!"
log_info ""
log_info "To use TLS configuration, update docker-compose.yml entrypoint:"
log_info "  --config-file=/opt/besu/keys/config-tls.toml"
log_info ""

