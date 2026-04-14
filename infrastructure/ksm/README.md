# KSM - Key Simulation Module

## Overview

KSM (Key Simulation Module) là REST API service cung cấp chữ ký số hậu lượng tử (Post-Quantum Cryptography) cho mạng blockchain liên ngân hàng.

**Tech Stack:** Java 17, Spring Boot 3.2, Dilithium (PQC)

## Quick Start

### Build

```bash
# Option 1: With Docker (no Maven needed)
./build.sh

# Option 2: With local Maven
mvn clean package -DskipTests
```

### Run

```bash
# Option 1: With Docker Compose (recommended)
cd ../Besu-hyperledger
docker-compose up -d ksm

# Option 2: Standalone
java -jar target/ksm-1.0.0.jar
```

### Test

```bash
# Health check
curl http://localhost:8080/ksm/health

# Generate key
curl -X POST http://localhost:8080/ksm/generateKey \
  -H "Content-Type: application/json" \
  -d '{"entityId":"vietcombank"}'

# Sign transaction
curl -X POST http://localhost:8080/ksm/sign \
  -H "Content-Type: application/json" \
  -d '{"entityId":"vietcombank","message":"Test transaction"}'
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/ksm/health` | Health check |
| POST | `/ksm/generateKey` | Generate PQC key pair |
| POST | `/ksm/sign` | Sign transaction |
| POST | `/ksm/verify` | Verify signature |
| POST | `/ksm/createSignedTransaction` | Create signed transaction |
| GET | `/ksm/publicKey/{entityId}` | Get public key |

## Architecture

```
GUI → Bridge Layer (TypeScript) → KSM Service → Blockchain
```

## Documentation

See [RUNBOOK.md](../docs/guides/RUNBOOK.md) - Bước 0B for full setup guide.

