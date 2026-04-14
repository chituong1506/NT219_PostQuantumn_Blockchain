#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# TLS 1.3 Testing Script
# Verify TLS configuration is working correctly
# ============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CA_CERT="$BASE_DIR/config/tls/ca/certs/sbv-root-ca.crt"

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# ============================================================================
# Test 1: Check if CA certificate exists
# ============================================================================
test_ca_exists() {
    log_test "Checking if SBV Root CA exists..."
    
    if [ -f "$CA_CERT" ]; then
        log_info "SBV Root CA found: $CA_CERT"
        
        # Show CA details
        echo ""
        echo "CA Certificate Details:"
        openssl x509 -in "$CA_CERT" -noout -subject -issuer -dates | sed 's/^/  /'
        echo ""
        return 0
    else
        log_error "SBV Root CA not found!"
        log_warn "Run: ./scripts/generate_tls13_certs.sh"
        return 1
    fi
}

# ============================================================================
# Test 2: Verify certificate chains
# ============================================================================
test_certificate_chains() {
    log_test "Verifying certificate chains..."
    
    local nodes=(sbv vietcombank vietinbank bidv rpcnode member1besu member2besu member3besu)
    local failed=0
    
    for node in "${nodes[@]}"; do
        local cert="$BASE_DIR/config/tls/$node/${node}-server-chain.crt"
        
        if [ -f "$cert" ]; then
            if openssl verify -CAfile "$CA_CERT" "$cert" > /dev/null 2>&1; then
                log_info "$node: Certificate chain valid"
            else
                log_error "$node: Certificate chain invalid!"
                failed=$((failed + 1))
            fi
        else
            log_error "$node: Certificate not found!"
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    if [ $failed -eq 0 ]; then
        log_info "All certificate chains are valid"
        return 0
    else
        log_error "$failed certificate chain(s) failed validation"
        return 1
    fi
}

# ============================================================================
# Test 3: Check if Besu nodes are running
# ============================================================================
test_nodes_running() {
    log_test "Checking if Besu nodes are running..."
    
    local nodes=(sbv vietcombank vietinbank bidv rpcnode member1besu member2besu member3besu)
    local running=0
    
    for node in "${nodes[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "$node"; then
            log_info "$node: Running"
            running=$((running + 1))
        else
            log_warn "$node: Not running"
        fi
    done
    
    echo ""
    log_info "$running / ${#nodes[@]} nodes are running"
    
    if [ $running -eq 0 ]; then
        log_warn "No nodes running. Start with: docker-compose up -d"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Test 4: Test TLS connection to rpcnode
# ============================================================================
test_tls_connection() {
    log_test "Testing TLS 1.3 connection to rpcnode..."
    
    # Check if rpcnode is running
    if ! docker ps --format '{{.Names}}' | grep -q "rpcnode"; then
        log_warn "rpcnode is not running. Skipping TLS connection test."
        log_warn "Start nodes with: docker-compose up -d"
        return 0
    fi
    
    # Wait a bit for node to be ready
    sleep 2
    
    # Test TLS connection
    echo ""
    echo "Testing HTTPS connection to localhost:8545..."
    
    local output
    output=$(echo "Q" | timeout 5 openssl s_client -connect localhost:8545 \
        -tls1_3 \
        -CAfile "$CA_CERT" 2>&1 || true)
    
    # Check for connection errors first
    if echo "$output" | grep -qi "Connection refused\|connect:errno"; then
        log_error "Cannot connect to localhost:8545"
        log_warn "Node may not be listening on this port or TLS may not be enabled"
        log_warn "Check node logs: docker logs rpcnode | grep -i tls"
        return 1
    fi
    
    if echo "$output" | grep -q "Verify return code: 0 (ok)"; then
        log_info "TLS connection successful!"
        
        # Extract protocol and cipher - more robust parsing
        local protocol=$(echo "$output" | grep -i "Protocol" | head -1 | sed -n 's/.*Protocol[[:space:]]*:[[:space:]]*\([^[:space:]]*\).*/\1/p')
        local cipher=$(echo "$output" | grep -i "Cipher" | head -1 | sed -n 's/.*Cipher[[:space:]]*:[[:space:]]*\([^[:space:]]*\).*/\1/p')
        
        # Alternative extraction if first method fails
        if [ -z "$protocol" ]; then
            protocol=$(echo "$output" | grep -i "New, TLSv" | head -1 | sed -n 's/.*New, \(TLSv[0-9.]*\).*/\1/p')
        fi
        if [ -z "$cipher" ]; then
            cipher=$(echo "$output" | grep -i "Cipher is" | head -1 | sed -n 's/.*Cipher is[[:space:]]*\([^[:space:]]*\).*/\1/p')
        fi
        
        # Try to get from handshake info
        if [ -z "$protocol" ]; then
            protocol=$(echo "$output" | grep -i "Protocol.*TLS" | head -1 | sed -n 's/.*\(TLSv[0-9.]*\).*/\1/p')
        fi
        if [ -z "$cipher" ]; then
            cipher=$(echo "$output" | grep -i "Cipher.*:" | head -1 | sed -n 's/.*Cipher.*:[[:space:]]*\([^[:space:]]*\).*/\1/p')
        fi
        
        echo ""
        echo "Connection Details:"
        echo "  Protocol: ${protocol:-unknown}"
        echo "  Cipher:   ${cipher:-unknown}"
        echo ""
        
        # Check if using TLS 1.3 and AES-GCM-256
        if echo "$protocol" | grep -qi "TLSv1.3\|TLS.*1.3"; then
            log_info "Using TLS 1.3 ✓"
        elif [ -n "$protocol" ] && [ "$protocol" != "unknown" ]; then
            log_error "Not using TLS 1.3! Current: $protocol"
        else
            log_warn "Could not determine TLS protocol version"
            log_warn "This may indicate TLS is not enabled or connection failed"
        fi
        
        if echo "$cipher" | grep -qi "AES.*GCM\|TLS_AES"; then
            log_info "Using AES-GCM cipher ✓"
        elif [ -n "$cipher" ] && [ "$cipher" != "unknown" ]; then
            log_warn "Not using AES-GCM cipher! Current: $cipher"
        else
            log_warn "Could not determine cipher suite"
        fi
        
        return 0
    else
        log_error "TLS connection failed!"
        echo ""
        echo "Error details:"
        echo "$output" | grep -E "error|verify|SSL|handshake" | head -10 | sed 's/^/  /'
        echo ""
        log_warn "Possible causes:"
        log_warn "  1. TLS may not be enabled in node configuration"
        log_warn "  2. Certificate files may not be accessible in container"
        log_warn "  3. Node may not be fully started yet"
        log_warn "Check: docker logs rpcnode | grep -i 'tls\|config-tls'"
        return 1
    fi
}

# ============================================================================
# Test 5: Test JSON-RPC over TLS
# ============================================================================
test_jsonrpc_tls() {
    log_test "Testing JSON-RPC over TLS..."
    
    if ! docker ps --format '{{.Names}}' | grep -q "rpcnode"; then
        log_warn "rpcnode is not running. Skipping JSON-RPC test."
        log_warn "Start nodes with: docker-compose up -d"
        return 0
    fi
    
    # Wait a bit for node to be ready
    sleep 2
    
    # Check curl version and TLS 1.3 support
    local curl_version=$(curl --version | head -1 | grep -oE 'curl [0-9]+\.[0-9]+' | cut -d' ' -f2)
    local curl_major=$(echo "$curl_version" | cut -d'.' -f1)
    local curl_minor=$(echo "$curl_version" | cut -d'.' -f2)
    local tls13_supported=false
    
    if [ -n "$curl_major" ] && [ -n "$curl_minor" ]; then
        if [ "$curl_major" -gt 7 ] || ([ "$curl_major" -eq 7 ] && [ "$curl_minor" -ge 52 ]); then
            tls13_supported=true
        fi
    fi
    
    # Test eth_blockNumber on rpcnode (port 8545)
    echo ""
    echo "Testing JSON-RPC on localhost:8545 (rpcnode)..."
    echo "Curl version: $curl_version (TLS 1.3 support: $tls13_supported)"
    
    local response
    local curl_error
    
    # Try with TLS 1.3 if supported, otherwise use default
    if [ "$tls13_supported" = "true" ]; then
        response=$(curl -s --cacert "$CA_CERT" \
            --tlsv1.3 \
            --tls-max 1.3 \
            -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            https://localhost:8545 2>&1)
        curl_error=$?
    else
        # Fallback: try without explicit TLS version (will negotiate)
        log_warn "Curl version may not support --tlsv1.3 flag, trying without it..."
        response=$(curl -s --cacert "$CA_CERT" \
            -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            https://localhost:8545 2>&1)
        curl_error=$?
    fi
    
    if [ $curl_error -ne 0 ]; then
        log_error "JSON-RPC request failed (curl error: $curl_error)!"
        echo ""
        echo "Error details:"
        echo "$response" | head -5
        echo ""
        
        # Provide specific troubleshooting based on error
        if echo "$response" | grep -qi "SSL\|certificate\|verify"; then
            log_warn "SSL/Certificate issue detected. Possible causes:"
            log_warn "  1. Node may not be using TLS (check if config-tls.toml exists)"
            log_warn "  2. Certificate path may be incorrect"
            log_warn "  3. Node may not be fully started yet"
        elif echo "$response" | grep -qi "Connection refused\|Couldn't connect"; then
            log_warn "Connection refused. Node may not be listening on port 8545"
            log_warn "Check node logs: docker logs rpcnode"
        fi
        
        log_warn "Note: If rpcnode is not accessible, try testing sbv node on port 21001"
        return 1
    fi
    
    if echo "$response" | grep -q '"result"'; then
        local block_number=$(echo "$response" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
        log_info "JSON-RPC working! Current block: $block_number"
        return 0
    elif echo "$response" | grep -q '"error"'; then
        log_error "JSON-RPC returned an error!"
        echo "Response: $response"
        return 1
    else
        log_error "JSON-RPC request failed - unexpected response!"
        echo "Response: $response"
        return 1
    fi
}

# ============================================================================
# Test 6: Test JSON-RPC on sbv node (port 21001)
# ============================================================================
test_jsonrpc_sbv() {
    log_test "Testing JSON-RPC over TLS on sbv node (port 21001)..."
    
    if ! docker ps --format '{{.Names}}' | grep -q "besu-hyperledger-sbv\|^sbv$"; then
        log_warn "sbv node is not running. Skipping sbv JSON-RPC test."
        log_warn "Start nodes with: docker-compose up -d"
        return 0
    fi
    
    # Wait a bit for node to be ready
    sleep 2
    
    # Check curl version and TLS 1.3 support
    local curl_version=$(curl --version | head -1 | grep -oE 'curl [0-9]+\.[0-9]+' | cut -d' ' -f2)
    local curl_major=$(echo "$curl_version" | cut -d'.' -f1)
    local curl_minor=$(echo "$curl_version" | cut -d'.' -f2)
    local tls13_supported=false
    
    if [ -n "$curl_major" ] && [ -n "$curl_minor" ]; then
        if [ "$curl_major" -gt 7 ] || ([ "$curl_major" -eq 7 ] && [ "$curl_minor" -ge 52 ]); then
            tls13_supported=true
        fi
    fi
    
    # Test eth_blockNumber on sbv (port 21001)
    echo ""
    echo "Testing JSON-RPC on localhost:21001 (sbv)..."
    echo "Curl version: $curl_version (TLS 1.3 support: $tls13_supported)"
    
    local response
    local curl_error
    
    # Try with TLS 1.3 if supported, otherwise use default
    if [ "$tls13_supported" = "true" ]; then
        response=$(curl -s --cacert "$CA_CERT" \
            --tlsv1.3 \
            --tls-max 1.3 \
            -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            https://localhost:21001 2>&1)
        curl_error=$?
    else
        # Fallback: try without explicit TLS version (will negotiate)
        log_warn "Curl version may not support --tlsv1.3 flag, trying without it..."
        response=$(curl -s --cacert "$CA_CERT" \
            -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            https://localhost:21001 2>&1)
        curl_error=$?
    fi
    
    if [ $curl_error -ne 0 ]; then
        log_error "JSON-RPC request failed (curl error: $curl_error)!"
        echo ""
        echo "Error details:"
        echo "$response" | head -5
        echo ""
        
        # Provide specific troubleshooting based on error
        if echo "$response" | grep -qi "SSL\|certificate\|verify"; then
            log_warn "SSL/Certificate issue detected. Possible causes:"
            log_warn "  1. Node may not be using TLS (check if config-tls.toml exists)"
            log_warn "  2. Certificate path may be incorrect"
            log_warn "  3. Node may not be fully started yet"
        elif echo "$response" | grep -qi "Connection refused\|Couldn't connect"; then
            log_warn "Connection refused. Node may not be listening on port 21001"
            log_warn "Check node logs: docker logs sbv"
        fi
        
        return 1
    fi
    
    if echo "$response" | grep -q '"result"'; then
        local block_number=$(echo "$response" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
        log_info "JSON-RPC working on sbv! Current block: $block_number"
        return 0
    elif echo "$response" | grep -q '"error"'; then
        log_error "JSON-RPC returned an error!"
        echo "Response: $response"
        return 1
    else
        log_error "JSON-RPC request failed - unexpected response!"
        echo "Response: $response"
        return 1
    fi
}

# ============================================================================
# Test 7: Test TLS 1.2 rejection
# ============================================================================
test_tls12_rejection() {
    log_test "Testing TLS 1.2 rejection (should fail)..."
    
    if ! docker ps --format '{{.Names}}' | grep -q "rpcnode"; then
        log_warn "rpcnode is not running. Skipping TLS 1.2 rejection test."
        return 0
    fi
    
    # Try to connect with TLS 1.2 (should fail)
    if timeout 3 openssl s_client -connect localhost:8545 \
        -tls1_2 \
        -CAfile "$CA_CERT" > /dev/null 2>&1; then
        log_error "TLS 1.2 was accepted! Should be rejected."
        return 1
    else
        log_info "TLS 1.2 correctly rejected ✓"
        return 0
    fi
}

# ============================================================================
# Main execution
# ============================================================================
main() {
    echo ""
    echo "=========================================="
    echo "  TLS 1.3 Configuration Test Suite"
    echo "=========================================="
    echo ""
    
    local total_tests=0
    local passed_tests=0
    
    # Run tests
    tests=(
        "test_ca_exists"
        "test_certificate_chains"
        "test_nodes_running"
        "test_tls_connection"
        "test_jsonrpc_tls"
        "test_jsonrpc_sbv"
        "test_tls12_rejection"
    )
    
    for test in "${tests[@]}"; do
        total_tests=$((total_tests + 1))
        echo ""
        
        if $test; then
            passed_tests=$((passed_tests + 1))
        fi
        
        echo ""
        echo "----------------------------------------"
    done
    
    # Summary
    echo ""
    echo "=========================================="
    echo "  Test Summary"
    echo "=========================================="
    echo ""
    echo "Total tests:  $total_tests"
    echo "Passed:       $passed_tests"
    echo "Failed:       $((total_tests - passed_tests))"
    echo ""
    
    if [ $passed_tests -eq $total_tests ]; then
        log_info "All tests passed! TLS 1.3 is configured correctly."
        echo ""
        return 0
    else
        log_error "Some tests failed. Please check the configuration."
        echo ""
        echo "Troubleshooting:"
        echo "  1. Make sure certificates are generated: ./scripts/generate_tls13_certs.sh"
        echo "  2. Make sure nodes are running: docker-compose up -d"
        echo "  3. Check node logs: docker logs rpcnode"
        echo "  4. Read documentation: docs/deployment/TLS13_SETUP_GUIDE.md"
        echo ""
        return 1
    fi
}

# Run main function
main "$@"

