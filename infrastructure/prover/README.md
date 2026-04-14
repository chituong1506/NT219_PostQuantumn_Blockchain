# ZKP Prover - Zero-Knowledge Proof Service

## Tổng quan

ZKP Prover service cung cấp khả năng tạo và xác minh Zero-Knowledge Proofs (ZKP) cho các giao dịch blockchain. Hiện tại, service tập trung vào việc chứng minh rằng **balance > amount** mà không tiết lộ giá trị balance thực tế.

## Tính năng

- ✅ Generate balance proof: Chứng minh balance > amount
- ✅ Verify balance proof: Xác minh proof trên server
- ✅ REST API: Dễ dàng tích hợp với các ứng dụng khác
- ✅ Privacy: Không tiết lộ giá trị balance thực tế

## Cấu trúc

```
prover/
├── src/
│   ├── main.rs              # Entry point
│   ├── lib.rs               # Library exports
│   ├── balance_proof/       # Balance proof module
│   │   └── mod.rs           # Balance proof implementation
│   └── api/                 # REST API
│       └── mod.rs           # API endpoints
├── Cargo.toml              # Dependencies
└── README.md               # This file
```

## API Endpoints

### Health Check
```bash
GET /health
```

Response:
```json
{
  "status": "healthy",
  "service": "zkp-prover-balance",
  "version": "0.1.0"
}
```

### Generate Balance Proof
```bash
POST /balance/proof
Content-Type: application/json

{
  "user_address": "0x1234...",
  "amount": 500,
  "balance_commitment": "00000000000003e8secret_nonce_123",
  "secret_nonce": "secret_nonce_123"
}
```

Response:
```json
{
  "success": true,
  "proof": {
    "proof_bytes": [1, 2, 3, ...],
    "public_inputs": {
      "amount": 500,
      "commitment_hash": "abc123...",
      "user_address": "0x1234..."
    },
    "commitment_hash": "abc123..."
  },
  "message": "Balance proof generated successfully"
}
```

### Verify Balance Proof
```bash
POST /balance/verify
Content-Type: application/json

{
  "proof": {
    "proof_bytes": [1, 2, 3, ...],
    "public_inputs": {
      "amount": 500,
      "commitment_hash": "abc123...",
      "user_address": "0x1234..."
    },
    "commitment_hash": "abc123..."
  },
  "balance_commitment": "00000000000003e8secret_nonce_123",
  "secret_nonce": "secret_nonce_123"
}
```

Response:
```json
{
  "success": true,
  "verified": true,
  "message": "Proof verified successfully"
}
```

### Get All Proofs
```bash
GET /balance/proofs
```

### Get Status
```bash
GET /status
```

## Cách sử dụng

### 1. Build và chạy service

```bash
cd prover

# Build
cargo build --release

# Run
RUST_LOG=info ./target/release/zkp-prover
```

Service sẽ chạy tại `http://localhost:8081`

### 2. Tích hợp với GUI

GUI đã có sẵn `zkp-client.ts` để gọi ZKP Prover API:

```typescript
import { getZKPClient } from '@/lib/zkp-client';

const zkpClient = getZKPClient();

// Generate proof
const proof = await zkpClient.generateBalanceProof(
  userAddress,
  amount,
  balance,
  secretNonce
);

// Verify proof
const verified = await zkpClient.verifyBalanceProof(
  proof,
  balanceCommitment,
  secretNonce
);
```

### 3. Sử dụng trong Transfer

Function `transferWithZKP` trong `contract.ts` đã tích hợp ZKP:

```typescript
import { transferWithZKP } from '@/lib/contract';

const result = await transferWithZKP(
  fromPrivateKey,
  toAddress,
  amountVND,
  toBankCode,
  description,
  true // useZKP = true
);
```

## Smart Contract Integration

### BalanceVerifier Contract

Contract `BalanceVerifier.sol` được deploy để verify proofs on-chain:

```solidity
// Deploy BalanceVerifier
BalanceVerifier verifier = new BalanceVerifier();

// Set verifier in InterbankTransfer
interbankTransfer.setBalanceVerifier(address(verifier));
interbankTransfer.toggleZKP(true);
```

### Transfer với ZKP

```solidity
// Call transferWithZKP
interbankTransfer.transferWithZKP(
    to,
    amount,
    toBankCode,
    description,
    proofAmount,
    commitmentHash,
    proofBytes
);
```

## Cách hoạt động

1. **Balance Commitment**: 
   - Format: `hex(balance) + secret_nonce`
   - Ví dụ: `"00000000000003e8secret123"` = balance 1000 + secret "secret123"

2. **Proof Generation**:
   - Tạo hash từ `amount || diff || commitment || secret`
   - Diff = balance - amount (phải > 0)
   - Public inputs: amount, commitment_hash, user_address

3. **Verification**:
   - Verify proof hash matches
   - Verify commitment hash matches
   - Verify balance > amount constraint

## Lưu ý

- ⚠️ Implementation hiện tại là simplified version
- ⚠️ Trong production, cần full STARK verification
- ⚠️ Balance commitment format có thể thay đổi
- ⚠️ Cần tích hợp với blockchain để lấy balance thực tế

## Development

### Run tests

```bash
cargo test
```

### Check lints

```bash
cargo clippy
```

### Format code

```bash
cargo fmt
```

## Environment Variables

- `RUST_LOG`: Log level (default: `info`)
- `PORT`: Server port (default: `8081`)

## Tài liệu tham khảo

- [Winterfell Documentation](https://github.com/facebook/winterfell)
- [Zero-Knowledge Proofs](https://en.wikipedia.org/wiki/Zero-knowledge_proof)
- [STARK Protocol](https://eprint.iacr.org/2018/046)
