#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KSM Service Testing Script
# Test PQC operations: health, key generation, signing, verification
# ============================================================================

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

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

KSM_URL="http://localhost:8080/ksm"

# ============================================================================
# Test 1: Health Check
# ============================================================================
test_health() {
    log_test "Checking KSM service health..."
    
    response=$(curl -s "$KSM_URL/health" || echo "ERROR")
    
    if echo "$response" | grep -q '"status":"UP"'; then
        log_info "KSM service is UP"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
        return 0
    else
        log_error "KSM service is DOWN or not responding"
        echo "Response: $response"
        return 1
    fi
}

# ============================================================================
# Test 2: Generate Keys
# ============================================================================
test_generate_keys() {
    log_test "Generating PQC keys for banks..."
    
    local banks=("vietcombank" "vietinbank" "bidv")
    local failed=0
    
    for bank in "${banks[@]}"; do
        response=$(curl -s -X POST "$KSM_URL/generateKey" \
            -H "Content-Type: application/json" \
            -d "{\"entityId\":\"$bank\"}" || echo "ERROR")
        
        if echo "$response" | grep -q '"success":true'; then
            log_info "$bank: Key generated"
            echo "$response" | grep -o '"publicKeySize":[0-9]*' || true
        else
            log_error "$bank: Key generation failed"
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    if [ $failed -eq 0 ]; then
        log_info "All keys generated successfully"
        return 0
    else
        log_error "$failed key generation(s) failed"
        return 1
    fi
}

# ============================================================================
# Test 3: Sign Transaction
# ============================================================================
test_sign_transaction() {
    log_test "Signing a transaction..."
    
    response=$(curl -s -X POST "$KSM_URL/sign" \
        -H "Content-Type: application/json" \
        -d '{
            "entityId": "vietcombank",
            "message": "Transfer 1000000 VND to vietinbank"
        }' || echo "ERROR")
    
    if echo "$response" | grep -q '"success":true'; then
        log_info "Transaction signed successfully"
        
        # Extract signature for verification test
        signature=$(echo "$response" | grep -o '"signature":"[^"]*"' | cut -d'"' -f4)
        echo "Signature size: $(echo "$response" | grep -o '"signatureSize":[0-9]*' | cut -d':' -f2) bytes"
        
        # Save signature for next test
        echo "$signature" > /tmp/ksm_test_signature.txt
        return 0
    else
        log_error "Transaction signing failed"
        echo "Response: $response"
        return 1
    fi
}

# ============================================================================
# Test 4: Verify Signature
# ============================================================================
test_verify_signature() {
    log_test "Verifying signature..."
    
    if [ ! -f /tmp/ksm_test_signature.txt ]; then
        log_error "No signature file found. Run sign test first."
        return 1
    fi
    
    signature=$(cat /tmp/ksm_test_signature.txt)
    
    response=$(curl -s -X POST "$KSM_URL/verify" \
        -H "Content-Type: application/json" \
        -d "{
            \"entityId\": \"vietcombank\",
            \"message\": \"Transfer 1000000 VND to vietinbank\",
            \"signature\": \"$signature\",
            \"algorithm\": \"Dilithium3\"
        }" || echo "ERROR")
    
    if echo "$response" | grep -q '"valid":true'; then
        log_info "Signature is VALID ✓"
        return 0
    else
        log_error "Signature verification failed"
        echo "Response: $response"
        return 1
    fi
}

# ============================================================================
# Test 5: Create Signed Transaction
# ============================================================================
test_create_signed_transaction() {
    log_test "Creating signed transaction..."
    
    response=$(curl -s -X POST "$KSM_URL/createSignedTransaction" \
        -H "Content-Type: application/json" \
        -d '{
            "from": "vietcombank",
            "to": "vietinbank",
            "amount": 1000000,
            "description": "Test transfer"
        }' || echo "ERROR")
    
    if echo "$response" | grep -q '"success":true'; then
        log_info "Signed transaction created"
        echo "$response" | python3 -m json.tool 2>/dev/null | head -20 || echo "$response"
        return 0
    else
        log_error "Signed transaction creation failed"
        echo "Response: $response"
        return 1
    fi
}

# ============================================================================
# Test 6: Get Public Key
# ============================================================================
test_get_public_key() {
    log_test "Getting public key..."
    
    response=$(curl -s "$KSM_URL/publicKey/vietcombank" || echo "ERROR")
    
    if echo "$response" | grep -q '"success":true'; then
        log_info "Public key retrieved"
        echo "$response" | grep -o '"algorithm":"[^"]*"' || true
        echo "$response" | grep -o '"publicKeySize":[0-9]*' || true
        return 0
    else
        log_error "Failed to get public key"
        echo "Response: $response"
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    echo ""
    echo "=========================================="
    echo "  KSM Service Test Suite"
    echo "=========================================="
    echo ""
    
    local total_tests=0
    local passed_tests=0
    
    # Run tests
    tests=(
        "test_health"
        "test_generate_keys"
        "test_sign_transaction"
        "test_verify_signature"
        "test_create_signed_transaction"
        "test_get_public_key"
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
    
    # Cleanup
    rm -f /tmp/ksm_test_signature.txt
    
    if [ $passed_tests -eq $total_tests ]; then
        log_info "All tests passed! KSM service is working correctly."
        echo ""
        return 0
    else
        log_error "Some tests failed. Please check the KSM service."
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check if KSM service is running: docker ps | grep ksm"
        echo "  2. Check KSM logs: docker logs ksm-service"
        echo "  3. Restart KSM: docker-compose restart ksm"
        echo ""
        return 1
    fi
}

# Run main function
main "$@"

