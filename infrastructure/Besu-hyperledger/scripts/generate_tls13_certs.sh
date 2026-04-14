#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# TLS 1.3 Certificate Generation Script for Interbank Blockchain Network
# Based on: NT219_BaoCaoTienDo-2.pdf Section 6.2
# Reference: Week12_windows_apache_pq_tls_13_openssl_36_guide.md
# 
# Security Requirements:
# - TLS 1.3 with AES-GCM-256
# - Self-signed CA by SBV (State Bank of Vietnam)
# - Server certificates for all nodes
# ============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TLS_DIR="$BASE_DIR/config/tls"
CA_DIR="$TLS_DIR/ca"
PASSWORD="changeit"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# Step 1: Initialize Directory Structure
# ============================================================================
init_directories() {
    log_info "Initializing TLS directory structure..."
    
    rm -rf "$TLS_DIR"
    mkdir -p "$CA_DIR"/{certs,crl,newcerts,private}
    
    # CA database files
    touch "$CA_DIR/index.txt"
    touch "$CA_DIR/index.txt.attr"
    echo "1000" > "$CA_DIR/serial"
    echo "1000" > "$CA_DIR/crlnumber"
    
    chmod 700 "$CA_DIR/private"
    
    log_info "Directory structure created at: $TLS_DIR"
}

# ============================================================================
# Step 2: Create OpenSSL Configuration for CA
# ============================================================================
create_ca_config() {
    log_info "Creating OpenSSL CA configuration..."
    
    cat > "$CA_DIR/openssl-ca.cnf" << 'EOF'
# OpenSSL CA Configuration for SBV Root CA
# TLS 1.3 with AES-GCM-256

[ ca ]
default_ca = CA_default

[ CA_default ]
# Root directory of this CA
dir               = CA_DIR_PLACEHOLDER
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand

# Root CA key and certificate
private_key       = $dir/private/sbv-root-ca.key
certificate       = $dir/certs/sbv-root-ca.crt

# CRL settings
crlnumber         = $dir/crlnumber
crl               = $dir/crl/sbv-root-ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30

# Signing defaults
default_md        = sha384
default_days      = 825
preserve          = no
policy            = policy_loose
x509_extensions   = server_cert
copy_extensions   = copy

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
default_md          = sha384
distinguished_name  = req_dn
x509_extensions     = v3_ca
string_mask         = utf8only
prompt              = no

[ req_dn ]
countryName                = VN
stateOrProvinceName        = Ho Chi Minh City
localityName               = District 1
organizationName           = State Bank of Vietnam
organizationalUnitName     = Blockchain Infrastructure
commonName                 = SBV Root CA for Interbank Blockchain
emailAddress               = admin@sbv.gov.vn

[ v3_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical,CA:TRUE
keyUsage               = critical,digitalSignature,cRLSign,keyCertSign

[ server_cert ]
basicConstraints       = CA:FALSE
nsCertType             = server
nsComment              = "TLS 1.3 Server Certificate for Blockchain Node"
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage               = critical,digitalSignature,keyEncipherment
extendedKeyUsage       = serverAuth
crlDistributionPoints  = @crl_section

[ crl_ext ]
authorityKeyIdentifier = keyid:always

[ crl_section ]
URI.0 = http://sbv-ca.local/crl/sbv-root-ca.crl

[ alt_names_template ]
# Will be replaced per node
DNS.1 = localhost
IP.1  = 127.0.0.1
EOF

    # Replace placeholder with actual path
    sed -i "s|CA_DIR_PLACEHOLDER|$CA_DIR|g" "$CA_DIR/openssl-ca.cnf"
    
    log_info "CA configuration created at: $CA_DIR/openssl-ca.cnf"
}

# ============================================================================
# Step 3: Generate SBV Root CA (Self-Signed)
# ============================================================================
generate_root_ca() {
    log_info "Generating SBV Root CA private key (RSA 4096-bit)..."
    
    openssl genrsa -aes256 \
        -passout pass:$PASSWORD \
        -out "$CA_DIR/private/sbv-root-ca.key" 4096
    
    chmod 400 "$CA_DIR/private/sbv-root-ca.key"
    
    log_info "Generating SBV Root CA self-signed certificate (valid 10 years)..."
    
    openssl req -new -x509 \
        -config "$CA_DIR/openssl-ca.cnf" \
        -key "$CA_DIR/private/sbv-root-ca.key" \
        -passin pass:$PASSWORD \
        -out "$CA_DIR/certs/sbv-root-ca.crt" \
        -days 3650 \
        -sha384
    
    chmod 444 "$CA_DIR/certs/sbv-root-ca.crt"
    
    log_info "Root CA certificate created. Inspecting..."
    openssl x509 -in "$CA_DIR/certs/sbv-root-ca.crt" -noout -subject -issuer -dates
}

# ============================================================================
# Step 4: Generate Server Certificates for Each Node
# ============================================================================
generate_node_cert() {
    local node_name="$1"
    local node_ip="$2"
    local node_dns="$3"
    
    log_info "Generating certificate for node: $node_name"
    
    local node_dir="$TLS_DIR/$node_name"
    mkdir -p "$node_dir"
    
    # Create node-specific OpenSSL config with SANs
    cat > "$node_dir/openssl-node.cnf" << EOF
[ req ]
default_bits        = 4096
default_md          = sha384
distinguished_name  = req_dn
req_extensions      = v3_req
string_mask         = utf8only
prompt              = no

[ req_dn ]
countryName                = VN
stateOrProvinceName        = Ho Chi Minh City
localityName               = District 1
organizationName           = ${node_name^^} Bank
organizationalUnitName     = Blockchain Node
commonName                 = ${node_name}.interbank.local
emailAddress               = admin@${node_name}.bank.vn

[ v3_req ]
basicConstraints       = CA:FALSE
keyUsage               = critical,digitalSignature,keyEncipherment
extendedKeyUsage       = serverAuth,clientAuth
subjectAltName         = @alt_names

[ alt_names ]
DNS.1 = ${node_dns}
DNS.2 = ${node_name}
DNS.3 = ${node_name}.interbank.local
DNS.4 = localhost
IP.1  = ${node_ip}
IP.2  = 127.0.0.1
EOF

    # Generate private key (unencrypted for server use)
    log_info "  → Generating private key for $node_name..."
    openssl genrsa -out "$node_dir/${node_name}-server.key" 4096
    chmod 400 "$node_dir/${node_name}-server.key"
    
    # Generate CSR
    log_info "  → Creating CSR for $node_name..."
    openssl req -new \
        -config "$node_dir/openssl-node.cnf" \
        -key "$node_dir/${node_name}-server.key" \
        -out "$node_dir/${node_name}-server.csr"
    
    # Sign CSR with SBV Root CA
    log_info "  → Signing certificate with SBV Root CA..."
    openssl ca -batch \
        -config "$CA_DIR/openssl-ca.cnf" \
        -passin pass:$PASSWORD \
        -in "$node_dir/${node_name}-server.csr" \
        -out "$node_dir/${node_name}-server.crt" \
        -extensions v3_req \
        -extfile "$node_dir/openssl-node.cnf" \
        -days 825
    
    chmod 444 "$node_dir/${node_name}-server.crt"
    
    # Create certificate chain (server cert + root CA)
    log_info "  → Creating certificate chain..."
    cat "$node_dir/${node_name}-server.crt" \
        "$CA_DIR/certs/sbv-root-ca.crt" \
        > "$node_dir/${node_name}-server-chain.crt"
    
    # Create PKCS12 keystore for Java applications (Besu)
    log_info "  → Creating PKCS12 keystore..."
    openssl pkcs12 -export \
        -in "$node_dir/${node_name}-server-chain.crt" \
        -inkey "$node_dir/${node_name}-server.key" \
        -out "$node_dir/${node_name}-keystore.p12" \
        -name "${node_name}-server" \
        -passout pass:$PASSWORD
    
    # Create truststore with root CA
    log_info "  → Creating truststore..."
    keytool -import -noprompt \
        -alias sbv-root-ca \
        -file "$CA_DIR/certs/sbv-root-ca.crt" \
        -keystore "$node_dir/${node_name}-truststore.p12" \
        -storetype PKCS12 \
        -storepass $PASSWORD 2>/dev/null || true
    
    # Save password to file
    echo "$PASSWORD" > "$node_dir/password.txt"
    chmod 400 "$node_dir/password.txt"
    
    log_info "  ✓ Certificate generated for $node_name"
}

# ============================================================================
# Step 5: Generate Certificates for All Nodes
# ============================================================================
generate_all_node_certs() {
    log_info "Generating certificates for all blockchain nodes..."
    
    # Define nodes with their IPs (matching docker-compose.yml)
    declare -A NODES=(
        ["sbv"]="172.16.239.11"
        ["vietcombank"]="172.16.239.12"
        ["vietinbank"]="172.16.239.13"
        ["bidv"]="172.16.239.14"
        ["rpcnode"]="172.16.239.15"
        ["member1besu"]="172.16.239.16"
        ["member2besu"]="172.16.239.17"
        ["member3besu"]="172.16.239.18"
    )
    
    for node in "${!NODES[@]}"; do
        generate_node_cert "$node" "${NODES[$node]}" "$node"
    done
    
    log_info "All node certificates generated successfully!"
}

# ============================================================================
# Step 6: Create TLS Configuration Summary
# ============================================================================
create_summary() {
    log_info "Creating TLS configuration summary..."
    
    cat > "$TLS_DIR/README.md" << 'EOF'
# TLS 1.3 Certificate Infrastructure for Interbank Blockchain

## Overview

This directory contains TLS 1.3 certificates for the interbank blockchain network, following the security requirements specified in NT219_BaoCaoTienDo-2.pdf.

## Security Configuration

- **TLS Version**: TLS 1.3 only
- **Cipher Suite**: AES-GCM-256 (TLS_AES_256_GCM_SHA384)
- **Key Exchange**: ECDHE with X25519
- **Certificate Authority**: SBV (State Bank of Vietnam) - Self-Signed Root CA
- **Certificate Validity**: 825 days (server certs), 3650 days (root CA)
- **Key Size**: RSA 4096-bit
- **Hash Algorithm**: SHA-384

## Directory Structure

```
tls/
├── ca/                          # Root CA directory
│   ├── certs/
│   │   └── sbv-root-ca.crt     # Root CA certificate (distribute to all clients)
│   ├── private/
│   │   └── sbv-root-ca.key     # Root CA private key (KEEP SECRET!)
│   └── openssl-ca.cnf          # CA configuration
│
├── sbv/                         # SBV node certificates
│   ├── sbv-server.key          # Private key
│   ├── sbv-server.crt          # Server certificate
│   ├── sbv-server-chain.crt    # Certificate chain (cert + root CA)
│   ├── sbv-keystore.p12        # PKCS12 keystore for Besu
│   ├── sbv-truststore.p12      # Truststore with root CA
│   └── password.txt            # Keystore password
│
├── vietcombank/                 # Vietcombank node certificates
├── vietinbank/                  # Vietinbank node certificates
├── bidv/                        # BIDV node certificates
├── rpcnode/                     # RPC node certificates
├── member1besu/                 # Member 1 certificates
├── member2besu/                 # Member 2 certificates
└── member3besu/                 # Member 3 certificates
```

## Usage

### For Besu Nodes

Add to Besu startup command or config.toml:

```toml
# HTTP RPC with TLS
rpc-http-enabled=true
rpc-http-tls-enabled=true
rpc-http-tls-keystore-file="/config/tls/<node>/keystore.p12"
rpc-http-tls-keystore-password-file="/config/tls/<node>/password.txt"
rpc-http-tls-client-auth-enabled=true
rpc-http-tls-known-clients-file="/config/tls/<node>/truststore.p12"

# WebSocket with TLS
rpc-ws-enabled=true
rpc-ws-tls-enabled=true
rpc-ws-tls-keystore-file="/config/tls/<node>/keystore.p12"
rpc-ws-tls-keystore-password-file="/config/tls/<node>/password.txt"
```

### Testing TLS Connection

```bash
# Test HTTPS connection to a node
openssl s_client -connect localhost:8545 \
    -tls1_3 \
    -CAfile ca/certs/sbv-root-ca.crt \
    -showcerts

# Verify certificate chain
openssl verify -CAfile ca/certs/sbv-root-ca.crt \
    sbv/sbv-server-chain.crt
```

### Client Configuration

Clients connecting to the blockchain must trust the SBV Root CA:

```bash
# Import root CA to system trust store (Ubuntu/Debian)
sudo cp ca/certs/sbv-root-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# For Java applications
keytool -import -alias sbv-root-ca \
    -file ca/certs/sbv-root-ca.crt \
    -keystore $JAVA_HOME/lib/security/cacerts \
    -storepass changeit
```

## Security Notes

1. **Root CA Private Key**: The file `ca/private/sbv-root-ca.key` is encrypted with password "changeit". In production, use a strong password and store in HSM.

2. **Password Management**: All keystores use password "changeit". Change this in production!

3. **Certificate Rotation**: Server certificates are valid for 825 days. Plan rotation before expiry.

4. **Mutual TLS (mTLS)**: Current configuration supports client certificate authentication. Enable `rpc-http-tls-client-auth-enabled=true` for mTLS.

5. **TLS 1.3 Only**: Configuration enforces TLS 1.3. Older clients using TLS 1.2 will be rejected.

## Compliance

This TLS infrastructure meets the requirements specified in:
- NT219_BaoCaoTienDo-2.pdf, Section 6.2 (Deployment Components)
- TLS 1.3 with AES-GCM-256 encryption
- Self-signed CA infrastructure for consortium blockchain

## Regeneration

To regenerate all certificates:

```bash
cd /path/to/Besu-hyperledger
./scripts/generate_tls13_certs.sh
```

**Warning**: This will invalidate all existing certificates!
EOF

    log_info "Summary created at: $TLS_DIR/README.md"
}

# ============================================================================
# Step 7: Create Besu Configuration Helper
# ============================================================================
create_besu_config_helper() {
    log_info "Creating Besu TLS configuration helper..."
    
    cat > "$TLS_DIR/besu-tls-config.toml" << 'EOF'
# Besu TLS 1.3 Configuration Template
# Copy relevant sections to your node's config.toml

# ============================================================================
# HTTP JSON-RPC with TLS 1.3
# ============================================================================
rpc-http-enabled=true
rpc-http-host="0.0.0.0"
rpc-http-port=8545

# Enable TLS for HTTP RPC
rpc-http-tls-enabled=true
rpc-http-tls-keystore-file="/config/tls/<NODE_NAME>/<NODE_NAME>-keystore.p12"
rpc-http-tls-keystore-password-file="/config/tls/<NODE_NAME>/password.txt"

# Optional: Enable mutual TLS (client certificate authentication)
rpc-http-tls-client-auth-enabled=true
rpc-http-tls-known-clients-file="/config/tls/<NODE_NAME>/<NODE_NAME>-truststore.p12"

# TLS protocol version (TLS 1.3 only)
rpc-http-tls-protocols=["TLSv1.3"]

# Cipher suites (AES-GCM-256 preferred)
rpc-http-tls-cipher-suites=["TLS_AES_256_GCM_SHA384","TLS_AES_128_GCM_SHA256"]

# ============================================================================
# WebSocket with TLS 1.3
# ============================================================================
rpc-ws-enabled=true
rpc-ws-host="0.0.0.0"
rpc-ws-port=8546

# Enable TLS for WebSocket
rpc-ws-tls-enabled=true
rpc-ws-tls-keystore-file="/config/tls/<NODE_NAME>/<NODE_NAME>-keystore.p12"
rpc-ws-tls-keystore-password-file="/config/tls/<NODE_NAME>/password.txt"

# Optional: Enable mutual TLS for WebSocket
rpc-ws-tls-client-auth-enabled=true
rpc-ws-tls-known-clients-file="/config/tls/<NODE_NAME>/<NODE_NAME>-truststore.p12"

# TLS protocol version (TLS 1.3 only)
rpc-ws-tls-protocols=["TLSv1.3"]

# Cipher suites (AES-GCM-256 preferred)
rpc-ws-tls-cipher-suites=["TLS_AES_256_GCM_SHA384","TLS_AES_128_GCM_SHA256"]

# ============================================================================
# Notes:
# - Replace <NODE_NAME> with actual node name (sbv, vietcombank, etc.)
# - Ensure certificate files are mounted in Docker container
# - Test with: openssl s_client -connect <host>:8545 -tls1_3
# ============================================================================
EOF

    log_info "Besu config helper created at: $TLS_DIR/besu-tls-config.toml"
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    echo ""
    log_info "=========================================="
    log_info "TLS 1.3 Certificate Generation"
    log_info "Interbank Blockchain Network"
    log_info "=========================================="
    echo ""
    
    init_directories
    create_ca_config
    generate_root_ca
    
    echo ""
    log_info "Root CA generated successfully!"
    log_info "CA Certificate: $CA_DIR/certs/sbv-root-ca.crt"
    log_info "CA Private Key: $CA_DIR/private/sbv-root-ca.key (encrypted)"
    echo ""
    
    generate_all_node_certs
    create_summary
    create_besu_config_helper
    
    echo ""
    log_info "=========================================="
    log_info "✓ TLS Certificate Generation Complete!"
    log_info "=========================================="
    echo ""
    
    # Ask user if they want to install CA certificate to system trust store
    log_info "============================================================"
    log_info "🔐 Install CA Certificate to System Trust Store"
    log_info "============================================================"
    echo ""
    echo "To avoid browser certificate warnings, we can install the"
    echo "SBV Root CA to your system's trust store."
    echo ""
    echo "Benefits:"
    echo "  ✅ Browser automatically trusts https://localhost:21001"
    echo "  ✅ No more 'certificate not trusted' warnings"
    echo "  ✅ Better development experience"
    echo ""
    read -p "Do you want to install CA certificate to system? (y/N): " -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "📦 Installing CA certificate to system trust store..."
        
        # Detect OS
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux
            echo "Detected: Linux"
            
            if command -v update-ca-certificates &> /dev/null; then
                # Debian/Ubuntu
                sudo cp "$CA_DIR/certs/sbv-root-ca.crt" /usr/local/share/ca-certificates/sbv-root-ca.crt
                sudo update-ca-certificates
                echo "[SUCCESS] ✅ CA certificate installed successfully!"
                echo "   Location: /usr/local/share/ca-certificates/sbv-root-ca.crt"
            elif command -v update-ca-trust &> /dev/null; then
                # RHEL/CentOS/Fedora
                sudo cp "$CA_DIR/certs/sbv-root-ca.crt" /etc/pki/ca-trust/source/anchors/sbv-root-ca.crt
                sudo update-ca-trust
                echo "[SUCCESS] ✅ CA certificate installed successfully!"
                echo "   Location: /etc/pki/ca-trust/source/anchors/sbv-root-ca.crt"
            else
                log_error "Could not detect certificate management tool"
                echo "   Please install manually:"
                echo "   sudo cp $CA_DIR/certs/sbv-root-ca.crt /usr/local/share/ca-certificates/sbv-root-ca.crt"
                echo "   sudo update-ca-certificates"
            fi
            
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            echo "Detected: macOS"
            sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CA_DIR/certs/sbv-root-ca.crt"
            echo "[SUCCESS] ✅ CA certificate installed successfully!"
            echo "   Added to: System Keychain"
            
        else
            log_error "Unsupported OS: $OSTYPE"
            echo "   Please install manually. See: ../GUI/web/BROWSER_TLS_FIX.md"
        fi
        
        echo ""
        log_warn "IMPORTANT: Please restart your browser completely"
        echo "   (close all browser windows) for changes to take effect!"
        echo ""
        
    else
        echo "⏭️  Skipped CA installation"
        echo ""
        echo "If you change your mind, run:"
        echo "  sudo cp $CA_DIR/certs/sbv-root-ca.crt /usr/local/share/ca-certificates/sbv-root-ca.crt"
        echo "  sudo update-ca-certificates"
        echo "  # Then restart browser"
        echo ""
        echo "Or see: ../GUI/web/BROWSER_TLS_FIX.md for other solutions"
        echo ""
    fi
    
    log_info "============================================================"
    echo ""
    log_info "Next steps:"
    log_info "1. Review certificates in: $TLS_DIR"
    log_info "2. Read documentation: $TLS_DIR/README.md"
    log_info "3. Update Besu configuration with TLS settings"
    log_info "4. Update docker-compose.yml to mount TLS certificates"
    log_info "5. Test TLS connection with: openssl s_client"
    log_info "6. Open browser: https://localhost:21001 (should work without warning!)"
    echo ""
    log_warn "Security reminder: Change default password 'changeit' in production!"
    echo ""
}

# Run main function
main "$@"

