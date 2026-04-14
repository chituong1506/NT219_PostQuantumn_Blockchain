#!/usr/bin/env bash
set -euo pipefail

# Build KSM service using Docker (no need for local Maven)

echo "Building KSM service with Docker..."

docker run --rm \
  -v "$(pwd)":/app \
  -w /app \
  maven:3.9-eclipse-temurin-17 \
  mvn clean package -DskipTests

echo ""
echo "✓ Build complete!"
echo "JAR file: target/ksm-1.0.0.jar"

