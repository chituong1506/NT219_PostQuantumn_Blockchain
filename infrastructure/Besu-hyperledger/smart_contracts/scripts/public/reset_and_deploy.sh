#!/bin/bash

# Script tự động reset blockchain và deploy contract
# Usage: ./reset_and_deploy.sh

set -e  # Exit on error

echo "🔄 Bắt đầu reset blockchain và deploy contract..."
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get project root (assume script is in Besu-hyperledger/smart_contracts/scripts/public)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BESU_DIR="$( cd "$SCRIPT_DIR/../../../../" && pwd )"
SMART_CONTRACTS_DIR="$( cd "$SCRIPT_DIR/../.." && pwd )"

echo "📁 Project root: $BESU_DIR"
echo "📁 Smart contracts: $SMART_CONTRACTS_DIR"
echo ""

# Step 1: Reset blockchain
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}BƯỚC 1: RESET BLOCKCHAIN${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo ""

cd "$BESU_DIR"

echo "🛑 Dừng và xóa containers + volumes..."
docker-compose down -v

echo ""
echo "🚀 Khởi động lại blockchain..."
./run.sh > /dev/null 2>&1 &

echo "⏳ Đợi blockchain khởi động (30 giây)..."
sleep 30

echo "🔍 Kiểm tra blockchain đã sẵn sàng..."
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -X POST http://localhost:21001 \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Blockchain đã sẵn sàng!${NC}"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "   Đợi thêm 3 giây... ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 3
    else
        echo -e "${RED}❌ Blockchain chưa sẵn sàng sau $MAX_RETRIES lần thử${NC}"
        exit 1
    fi
done

echo ""

# Step 2: Deploy and init contract
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}BƯỚC 2: DEPLOY VÀ INIT CONTRACT${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo ""

cd "$SMART_CONTRACTS_DIR"

echo "🚀 Chạy script deploy_and_init.js..."
node scripts/public/deploy_and_init.js

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ HOÀN TẤT!${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "✅ Blockchain đã được reset"
    echo "✅ Contract đã được deploy và init"
    echo "✅ Tất cả users đã có 100 ETH trong contract"
    echo ""
    echo "🚀 Bây giờ bạn có thể sử dụng GUI để transfer tiền!"
else
    echo ""
    echo -e "${RED}❌ Có lỗi xảy ra khi deploy contract${NC}"
    exit 1
fi

