# 🔐 Deploy Smart Contracts với TLS

## Vấn đề

Khi blockchain chạy với TLS 1.3, các scripts deploy cần kết nối qua HTTPS với self-signed certificates.

**Node.js 22 có issue:** `fetch()` API không respect custom HTTPS agent properly, gây lỗi với self-signed certificates.

## Giải pháp

### Option 1: Dùng curl để deploy (Recommended - Nhanh nhất)

```bash
# Disable TLS verification trong Node.js
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Deploy
cd smart_contracts
RPC_ENDPOINT=https://localhost:21001 node scripts/public/deploy_and_init.js
```

### Option 2: Deploy qua HTTP port (Nếu có)

Nếu có node không dùng TLS:

```bash
# Dùng member node hoặc node khác không có TLS
RPC_ENDPOINT=http://localhost:21002 node scripts/public/deploy_and_init.js
```

### Option 3: Tạm tắt TLS để deploy

```bash
cd ../Besu-hyperledger

# 1. Backup TLS config
mv config/tls config/tls.backup

# 2. Restart nodes (sẽ chạy HTTP)
docker-compose restart sbv vietcombank vietinbank bidv

# 3. Deploy
cd smart_contracts
node scripts/public/deploy_and_init.js

# 4. Restore TLS
cd ../Besu-hyperledger
mv config/tls.backup config/tls
docker-compose restart sbv vietcombank vietinbank bidv
```

### Option 4: Dùng axios thay vì fetch (Best long-term)

Install axios:

```bash
cd smart_contracts
npm install axios
```

Update `tls-provider.js` để dùng axios (TODO).

## Quick Deploy Commands

### Với TLS (Self-signed)

```bash
# Set environment để ignore self-signed cert
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Deploy
cd /home/quy/project/NT219_Project/Besu-hyperledger/smart_contracts
RPC_ENDPOINT=https://localhost:21001 node scripts/public/deploy_and_init.js

# Unset sau khi xong
unset NODE_TLS_REJECT_UNAUTHORIZED
```

### Không TLS

```bash
cd /home/quy/project/NT219_Project/Besu-hyperledger/smart_contracts
RPC_ENDPOINT=http://localhost:21001 node scripts/public/deploy_and_init.js
```

## Test TLS Connection

```bash
# Test với HTTP
RPC_ENDPOINT=http://localhost:21001 node scripts/test_tls_connection.js

# Test với HTTPS (sẽ fail với self-signed)
RPC_ENDPOINT=https://localhost:21001 node scripts/test_tls_connection.js

# Test với HTTPS + ignore cert
NODE_TLS_REJECT_UNAUTHORIZED=0 RPC_ENDPOINT=https://localhost:21001 node scripts/test_tls_connection.js
```

## Lưu ý

⚠️ **`NODE_TLS_REJECT_UNAUTHORIZED=0` chỉ dùng cho development/testing!**

Trong production:
1. Dùng proper CA-signed certificates
2. Hoặc import self-signed CA vào system trust store
3. Hoặc dùng axios với custom CA certificate

## Status

✅ **TLS provider scripts đã được tạo:**
- `scripts/tls-provider.js` - Helper module
- `scripts/test_tls_connection.js` - Test script
- `scripts/public/deploy_interbank.js` - Updated với TLS support

⏳ **TODO:**
- Integrate axios để properly handle self-signed certs
- Update tất cả scripts khác để dùng tls-provider

## Workaround hiện tại

```bash
# Deploy với TLS
export NODE_TLS_REJECT_UNAUTHORIZED=0
cd smart_contracts
RPC_ENDPOINT=https://localhost:21001 node scripts/public/deploy_and_init.js
unset NODE_TLS_REJECT_UNAUTHORIZED
```

---

**See also:**
- [TLS13_SETUP_GUIDE.md](../docs/deployment/TLS13_SETUP_GUIDE.md)
- [RUNBOOK.md](../docs/guides/RUNBOOK.md)

