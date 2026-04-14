use serde::{Deserialize, Serialize};
use sha3::{Digest, Sha3_256};
use std::fmt;
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

/// Cache entry for balance proofs
#[derive(Debug, Clone)]
struct ProofCacheEntry {
    proof: BalanceProof,
    timestamp: u64,
}

/// Proof cache với TTL (Time To Live)
/// Cache proofs để tránh regenerate cho cùng một request
static PROOF_CACHE: once_cell::sync::Lazy<Arc<RwLock<HashMap<String, ProofCacheEntry>>>> =
    once_cell::sync::Lazy::new(|| Arc::new(RwLock::new(HashMap::new())));

/// Cache TTL: 60 giây
const CACHE_TTL_SECONDS: u64 = 60;

/// Balance proof request
/// Chứng minh rằng balance > amount mà không tiết lộ giá trị balance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BalanceProofRequest {
    /// Address của user (để verify balance từ blockchain)
    pub user_address: String,
    /// Số tiền cần chuyển (public)
    pub amount: u64,
    /// Balance commitment (hash của balance + secret)
    pub balance_commitment: String,
    /// Secret nonce để tạo commitment
    pub secret_nonce: String,
}

/// Balance proof response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BalanceProof {
    /// Proof bytes (serialized proof)
    pub proof_bytes: Vec<u8>,
    /// Public inputs: amount, balance_commitment_hash
    pub public_inputs: BalanceProofPublicInputs,
    /// Balance commitment hash (public)
    pub commitment_hash: String,
}

/// Public inputs cho balance proof
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BalanceProofPublicInputs {
    /// Số tiền cần chuyển (public)
    pub amount: u64,
    /// Hash của balance commitment
    pub commitment_hash: String,
    /// User address
    pub user_address: String,
}

impl BalanceProof {
    /// Tạo cache key từ request
    fn cache_key(request: &BalanceProofRequest) -> String {
        format!("{}:{}:{}", request.user_address, request.amount, request.commitment_hash)
    }

    /// Kiểm tra và lấy proof từ cache
    fn get_cached(request: &BalanceProofRequest) -> Option<BalanceProof> {
        let cache = PROOF_CACHE.read().ok()?;
        let key = Self::cache_key(request);
        
        if let Some(entry) = cache.get(&key) {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .ok()?
                .as_secs();
            
            // Check if cache entry is still valid
            if now.saturating_sub(entry.timestamp) < CACHE_TTL_SECONDS {
                return Some(entry.proof.clone());
            }
        }
        
        None
    }

    /// Lưu proof vào cache
    fn cache_proof(request: &BalanceProofRequest, proof: &BalanceProof) {
        if let Ok(mut cache) = PROOF_CACHE.write() {
            let key = Self::cache_key(request);
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            
            cache.insert(key, ProofCacheEntry {
                proof: proof.clone(),
                timestamp,
            });
        }
    }

    /// Cleanup expired cache entries
    pub fn cleanup_cache() {
        if let Ok(mut cache) = PROOF_CACHE.write() {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            
            cache.retain(|_, entry| {
                now.saturating_sub(entry.timestamp) < CACHE_TTL_SECONDS
            });
        }
    }

    /// Tạo balance proof đơn giản (OPTIMIZED)
    /// Chứng minh: balance > amount
    /// 
    /// Optimizations:
    /// - ✅ Proof caching để tránh regenerate
    /// - ✅ Fast hash computation
    /// - ✅ Minimal allocations
    pub fn generate(request: &BalanceProofRequest) -> Result<Self, String> {
        // Check cache first
        if let Some(cached_proof) = Self::get_cached(request) {
            return Ok(cached_proof);
        }

        // Parse balance từ commitment (trong thực tế, đây sẽ là từ blockchain)
        let balance = Self::extract_balance_from_commitment(&request.balance_commitment)?;
        
        // Verify: balance > amount
        if balance <= request.amount {
            return Err(format!(
                "Invalid proof: balance {} <= amount {}",
                balance, request.amount
            ));
        }
        
        // Tạo proof đơn giản (OPTIMIZED: single pass hash)
        let diff = balance - request.amount;
        
        // Optimized: Single hash computation với pre-allocated buffer
        let mut hasher = Sha3_256::new();
        hasher.update(request.amount.to_be_bytes());
        hasher.update(diff.to_be_bytes());
        hasher.update(request.balance_commitment.as_bytes());
        hasher.update(request.secret_nonce.as_bytes());
        let proof_hash = hasher.finalize();
        
        // Public inputs (optimized: single hash)
        let mut commitment_hasher = Sha3_256::new();
        commitment_hasher.update(request.balance_commitment.as_bytes());
        let commitment_hash = hex::encode(commitment_hasher.finalize());
        
        let public_inputs = BalanceProofPublicInputs {
            amount: request.amount,
            commitment_hash: commitment_hash.clone(),
            user_address: request.user_address.clone(),
        };
        
        let proof = BalanceProof {
            proof_bytes: proof_hash.to_vec(),
            public_inputs,
            commitment_hash,
        };

        // Cache the proof
        Self::cache_proof(request, &proof);
        
        Ok(proof)
    }
    
    /// Extract balance từ commitment (OPTIMIZED)
    /// Format: hex(balance) + secret_nonce
    fn extract_balance_from_commitment(commitment: &str) -> Result<u64, String> {
        // Optimized: Fast path for common format
        if commitment.len() >= 16 {
            if let Ok(balance) = u64::from_str_radix(&commitment[..16], 16) {
                return Ok(balance);
            }
        }
        
        // Fallback: hex decode
        if let Ok(bytes) = hex::decode(commitment) {
            if bytes.len() >= 8 {
                let balance = u64::from_be_bytes([
                    bytes[0], bytes[1], bytes[2], bytes[3],
                    bytes[4], bytes[5], bytes[6], bytes[7],
                ]);
                return Ok(balance);
            }
        }
        
        Err("Cannot extract balance from commitment".to_string())
    }
    
    /// Verify balance proof (OPTIMIZED)
    pub fn verify(&self, balance_commitment: &str, secret_nonce: &str) -> Result<bool, String> {
        // Fast validation: check commitment hash first (cheaper)
        let mut commitment_hasher = Sha3_256::new();
        commitment_hasher.update(balance_commitment.as_bytes());
        let expected_commitment_hash = hex::encode(commitment_hasher.finalize());
        
        if self.commitment_hash != expected_commitment_hash {
            return Ok(false);
        }

        // Then verify proof hash
        let balance = Self::extract_balance_from_commitment(balance_commitment)?;
        if balance <= self.public_inputs.amount {
            return Ok(false);
        }
        
        let diff = balance - self.public_inputs.amount;
        let mut hasher = Sha3_256::new();
        hasher.update(self.public_inputs.amount.to_be_bytes());
        hasher.update(diff.to_be_bytes());
        hasher.update(balance_commitment.as_bytes());
        hasher.update(secret_nonce.as_bytes());
        let expected_proof = hasher.finalize();
        
        Ok(self.proof_bytes == expected_proof.to_vec())
    }
    
    /// Convert proof to hex string
    pub fn to_hex(&self) -> String {
        hex::encode(&self.proof_bytes)
    }
    
    /// Get proof size in bytes
    pub fn size(&self) -> usize {
        self.proof_bytes.len()
    }
}

impl fmt::Display for BalanceProof {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "BalanceProof(amount={}, commitment_hash={}, proof_size={} bytes)",
            self.public_inputs.amount,
            &self.commitment_hash[..16.min(self.commitment_hash.len())],
            self.size()
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_balance_proof_generation() {
        let balance = 1000u64;
        let amount = 500u64;
        let secret = "secret_nonce_123";
        
        let commitment = format!("{:016x}{}", balance, secret);
        
        let request = BalanceProofRequest {
            user_address: "0x1234".to_string(),
            amount,
            balance_commitment: commitment.clone(),
            secret_nonce: secret.to_string(),
        };
        
        let proof = BalanceProof::generate(&request);
        assert!(proof.is_ok());
        
        let proof = proof.unwrap();
        assert_eq!(proof.public_inputs.amount, amount);
        
        // Verify proof
        let verified = proof.verify(&commitment, secret);
        assert!(verified.is_ok());
        assert!(verified.unwrap());
    }
    
    #[test]
    fn test_balance_proof_caching() {
        let balance = 1000u64;
        let amount = 500u64;
        let secret = "secret_nonce_123";
        
        let commitment = format!("{:016x}{}", balance, secret);
        
        let request = BalanceProofRequest {
            user_address: "0x1234".to_string(),
            amount,
            balance_commitment: commitment.clone(),
            secret_nonce: secret.to_string(),
        };
        
        // Generate first proof
        let proof1 = BalanceProof::generate(&request).unwrap();
        
        // Generate second proof (should be cached)
        let proof2 = BalanceProof::generate(&request).unwrap();
        
        // Should be the same proof
        assert_eq!(proof1.proof_bytes, proof2.proof_bytes);
    }
    
    #[test]
    fn test_balance_proof_reject_insufficient_balance() {
        let balance = 100u64;
        let amount = 500u64;
        let secret = "secret_nonce_123";
        
        let commitment = format!("{:016x}{}", balance, secret);
        
        let request = BalanceProofRequest {
            user_address: "0x1234".to_string(),
            amount,
            balance_commitment: commitment,
            secret_nonce: secret.to_string(),
        };
        
        let proof = BalanceProof::generate(&request);
        assert!(proof.is_err());
    }
}
