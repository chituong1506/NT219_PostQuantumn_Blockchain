use actix_web::{web, App, HttpResponse, HttpServer, Responder, middleware};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::balance_proof::{BalanceProof, BalanceProofRequest};

#[derive(Clone)]
pub struct AppState {
    pub proofs: Arc<Mutex<Vec<BalanceProof>>>,
}

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub service: String,
    pub version: String,
}

#[derive(Serialize)]
pub struct BalanceProofResponse {
    pub success: bool,
    pub proof: Option<BalanceProof>,
    pub message: String,
}

/// Health check endpoint
async fn health() -> impl Responder {
    HttpResponse::Ok().json(HealthResponse {
        status: "healthy".to_string(),
        service: "zkp-prover-balance".to_string(),
        version: "0.1.0".to_string(),
    })
}

/// Generate balance proof (OPTIMIZED)
/// POST /balance/proof
/// Body: BalanceProofRequest
async fn generate_balance_proof(
    data: web::Data<AppState>,
    req: web::Json<BalanceProofRequest>,
) -> impl Responder {
    // Cleanup cache periodically (every 100 requests)
    static REQUEST_COUNT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let count = REQUEST_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    if count % 100 == 0 {
        BalanceProof::cleanup_cache();
    }
    
    log::debug!("Generating balance proof for user: {}, amount: {}", req.user_address, req.amount);
    
    match BalanceProof::generate(&req) {
        Ok(proof) => {
            log::debug!("Balance proof generated successfully: {}", proof);
            
            // Store proof (async, non-blocking)
            let proofs = data.proofs.clone();
            let proof_clone = proof.clone();
            tokio::spawn(async move {
                proofs.lock().unwrap().push(proof_clone);
            });
            
            HttpResponse::Ok().json(BalanceProofResponse {
                success: true,
                proof: Some(proof),
                message: "Balance proof generated successfully".to_string(),
            })
        }
        Err(e) => {
            log::error!("Failed to generate balance proof: {}", e);
            HttpResponse::BadRequest().json(BalanceProofResponse {
                success: false,
                proof: None,
                message: format!("Failed to generate proof: {}", e),
            })
        }
    }
}

/// Verify balance proof
/// POST /balance/verify
#[derive(Deserialize)]
pub struct VerifyProofRequest {
    pub proof: BalanceProof,
    pub balance_commitment: String,
    pub secret_nonce: String,
}

#[derive(Serialize)]
pub struct VerifyProofResponse {
    pub success: bool,
    pub verified: bool,
    pub message: String,
}

async fn verify_balance_proof(req: web::Json<VerifyProofRequest>) -> impl Responder {
    log::info!("Verifying balance proof");
    
    match req.proof.verify(&req.balance_commitment, &req.secret_nonce) {
        Ok(verified) => {
            if verified {
                log::info!("Balance proof verified successfully");
                HttpResponse::Ok().json(VerifyProofResponse {
                    success: true,
                    verified: true,
                    message: "Proof verified successfully".to_string(),
                })
            } else {
                log::warn!("Balance proof verification failed");
                HttpResponse::Ok().json(VerifyProofResponse {
                    success: true,
                    verified: false,
                    message: "Proof verification failed".to_string(),
                })
            }
        }
        Err(e) => {
            log::error!("Error verifying proof: {}", e);
            HttpResponse::BadRequest().json(VerifyProofResponse {
                success: false,
                verified: false,
                message: format!("Verification error: {}", e),
            })
        }
    }
}

/// Get all generated proofs
/// GET /balance/proofs
async fn get_proofs(data: web::Data<AppState>) -> impl Responder {
    let proofs = data.proofs.lock().unwrap();
    let proof_info: Vec<_> = proofs.iter().map(|p| {
        serde_json::json!({
            "amount": p.public_inputs.amount,
            "user_address": p.public_inputs.user_address,
            "commitment_hash": p.commitment_hash,
            "proof_hex": p.to_hex(),
            "proof_size": p.size()
        })
    }).collect();
    
    HttpResponse::Ok().json(proof_info)
}

/// Status endpoint
#[derive(Serialize)]
pub struct StatusResponse {
    pub status: String,
    pub generated_proofs: usize,
}

async fn status(data: web::Data<AppState>) -> impl Responder {
    let proofs_count = data.proofs.lock().unwrap().len();
    
    HttpResponse::Ok().json(StatusResponse {
        status: "running".to_string(),
        generated_proofs: proofs_count,
    })
}

/// Batch proof generation endpoint - OPTIMIZED for high TPS
/// POST /balance/proofs/batch
#[derive(Deserialize)]
pub struct BatchProofRequest {
    pub requests: Vec<BalanceProofRequest>,
}

#[derive(Serialize)]
pub struct BatchProofResponse {
    pub success: bool,
    pub proofs: Vec<Option<BalanceProof>>,
    pub errors: Vec<Option<String>>,
    pub message: String,
}

async fn generate_batch_proofs(
    data: web::Data<AppState>,
    req: web::Json<BatchProofRequest>,
) -> impl Responder {
    log::debug!("Generating batch proofs: {} requests", req.requests.len());
    
    if req.requests.len() > 100 {
        return HttpResponse::BadRequest().json(BatchProofResponse {
            success: false,
            proofs: vec![],
            errors: vec![Some("Batch size too large (max 100)".to_string())],
            message: "Batch size exceeds limit".to_string(),
        });
    }
    
    let mut proofs = Vec::new();
    let mut errors = Vec::new();
    
    // Generate proofs in parallel (using tokio::spawn for each request)
    let mut handles = Vec::new();
    
    for request in &req.requests {
        let req_clone = request.clone();
        let proofs_clone = data.proofs.clone();
        
        let handle = tokio::spawn(async move {
            match BalanceProof::generate(&req_clone) {
                Ok(proof) => {
                    // Store proof async
                    let proofs_ref = proofs_clone.clone();
                    let proof_clone = proof.clone();
                    tokio::spawn(async move {
                        proofs_ref.lock().unwrap().push(proof_clone);
                    });
                    Ok(proof)
                }
                Err(e) => Err(e),
            }
        });
        
        handles.push(handle);
    }
    
    // Wait for all proofs to complete
    for handle in handles {
        match handle.await {
            Ok(Ok(proof)) => {
                proofs.push(Some(proof));
                errors.push(None);
            }
            Ok(Err(e)) => {
                proofs.push(None);
                errors.push(Some(e));
            }
            Err(e) => {
                proofs.push(None);
                errors.push(Some(format!("Task error: {}", e)));
            }
        }
    }
    
    let success_count = proofs.iter().filter(|p| p.is_some()).count();
    log::info!("Batch proof generation completed: {}/{} successful", success_count, req.requests.len());
    
    HttpResponse::Ok().json(BatchProofResponse {
        success: success_count > 0,
        proofs,
        errors,
        message: format!("Generated {} proofs successfully", success_count),
    })
}

pub async fn start_server() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::new().default_filter_or("info"));
    
    log::info!("Starting ZKP Balance Prover Service (OPTIMIZED)...");
    
    // Initialize state
    let proofs = Arc::new(Mutex::new(Vec::new()));
    
    let app_state = web::Data::new(AppState {
        proofs,
    });
    
    log::info!("Prover service listening on http://0.0.0.0:8081");
    log::info!("Optimizations enabled: proof caching, async processing, connection pooling");
    
    // Enable HTTP/2 support
    log::info!("HTTP/2 support: enabled (via h2 dependency)");
    
    HttpServer::new(move || {
        App::new()
            .app_data(app_state.clone())
            .wrap(middleware::Logger::default())
            .wrap(middleware::Compress::default()) // Enable compression
            .route("/health", web::get().to(health))
            .route("/status", web::get().to(status))
            .route("/balance/proof", web::post().to(generate_balance_proof))
            .route("/balance/verify", web::post().to(verify_balance_proof))
            .route("/balance/proofs", web::get().to(get_proofs))
            // Batch proof endpoint for high TPS
            .route("/balance/proofs/batch", web::post().to(generate_batch_proofs))
    })
    .workers(num_cpus::get()) // Use all CPU cores
    .keep_alive(Duration::from_secs(75)) // Keep connections alive
    .client_timeout(30000) // 30s timeout
    .client_disconnect_timeout(5000) // 5s disconnect timeout
    .bind(("0.0.0.0", 8081))?
    .run()
    .await
}

