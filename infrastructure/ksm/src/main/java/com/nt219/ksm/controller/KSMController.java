package com.nt219.ksm.controller;

import com.nt219.ksm.crypto.*;
import com.nt219.ksm.process.PQCProcessService;
import com.nt219.ksm.process.SignedTransaction;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

/**
 * REST API Controller for KSM operations
 */
@RestController
@RequestMapping("/ksm")
@CrossOrigin(origins = "*") // Allow requests from GUI
public class KSMController {
    
    private final PQCProcessService pqcService;
    
    @Autowired
    public KSMController(PQCProcessService pqcService) {
        this.pqcService = pqcService;
        System.out.println("[KSM] Controller initialized with PQC Process Service");
    }
    
    /**
     * Health check endpoint
     */
    @GetMapping("/health")
    public Map<String, Object> health() {
        Map<String, Object> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "KSM - Key Simulation Module");
        response.put("version", "1.0.0");
        response.put("algorithms", new String[]{
            "DILITHIUM2", "DILITHIUM3", "DILITHIUM5",
            "KYBER512", "KYBER768", "KYBER1024"
        });
        response.put("defaultSignature", "DILITHIUM3");
        response.put("defaultEncryption", "KYBER768");
        return response;
    }
    
    /**
     * Generate PQC key pair for an entity
     * 
     * POST /ksm/generateKey
     * Body: { "entityId": "vietcombank" }
     */
    @PostMapping("/generateKey")
    public Map<String, Object> generateKey(@RequestBody Map<String, String> request) {
        try {
            String entityId = request.get("entityId");
            
            if (entityId == null || entityId.trim().isEmpty()) {
                return createErrorResponse("entityId is required");
            }
            
            System.out.println("[KSM] Generating key pair for entity: " + entityId);
            
            PQCKeyPair keyPair = pqcService.generateKeyPairForEntity(entityId);
            
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("entityId", entityId);
            response.put("publicKey", Base64.getEncoder().encodeToString(keyPair.getPublicKey()));
            response.put("algorithm", keyPair.getAlgorithm());
            response.put("publicKeySize", keyPair.getPublicKey().length);
            response.put("message", "Key pair generated successfully");
            
            System.out.println("[KSM] ✓ Key pair generated for " + entityId);
            return response;
            
        } catch (Exception e) {
            System.err.println("[KSM] Error generating key: " + e.getMessage());
            return createErrorResponse("Key generation failed: " + e.getMessage());
        }
    }
    
    /**
     * Sign a transaction/message
     * 
     * POST /ksm/sign
     * Body: { 
     *   "entityId": "vietcombank",
     *   "message": "Transaction data here"
     * }
     */
    @PostMapping("/sign")
    public Map<String, Object> sign(@RequestBody Map<String, String> request) {
        try {
            String entityId = request.get("entityId");
            String message = request.get("message");
            
            if (entityId == null || message == null) {
                return createErrorResponse("entityId and message are required");
            }
            
            System.out.println("[KSM] Signing message for entity: " + entityId);
            
            PQCSignature signature = pqcService.signTransaction(entityId, message);
            
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("entityId", entityId);
            response.put("signature", Base64.getEncoder().encodeToString(signature.getSignature()));
            response.put("algorithm", signature.getAlgorithm());
            response.put("signatureSize", signature.getSignature().length);
            response.put("timestamp", System.currentTimeMillis());
            response.put("message", "Transaction signed successfully");
            
            System.out.println("[KSM] ✓ Transaction signed for " + entityId);
            return response;
            
        } catch (Exception e) {
            System.err.println("[KSM] Error signing transaction: " + e.getMessage());
            return createErrorResponse("Signing failed: " + e.getMessage());
        }
    }
    
    /**
     * Verify a signature
     * 
     * POST /ksm/verify
     * Body: {
     *   "entityId": "vietcombank",
     *   "message": "Transaction data here",
     *   "signature": "base64_signature",
     *   "algorithm": "Dilithium3"
     * }
     */
    @PostMapping("/verify")
    public Map<String, Object> verify(@RequestBody Map<String, String> request) {
        try {
            String entityId = request.get("entityId");
            String message = request.get("message");
            String signatureBase64 = request.get("signature");
            String algorithm = request.get("algorithm");
            
            if (entityId == null || message == null || signatureBase64 == null) {
                return createErrorResponse("entityId, message, and signature are required");
            }
            
            System.out.println("[KSM] Verifying signature for entity: " + entityId);
            
            byte[] signatureBytes = Base64.getDecoder().decode(signatureBase64);
            PQCSignature signature = new PQCSignature(signatureBytes, algorithm);
            
            boolean isValid = pqcService.verifyTransaction(entityId, message, signature);
            
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("entityId", entityId);
            response.put("valid", isValid);
            response.put("algorithm", algorithm);
            response.put("timestamp", System.currentTimeMillis());
            response.put("message", isValid ? "Signature is valid" : "Signature is invalid");
            
            System.out.println("[KSM] ✓ Verification result: " + isValid);
            return response;
            
        } catch (Exception e) {
            System.err.println("[KSM] Error verifying signature: " + e.getMessage());
            return createErrorResponse("Verification failed: " + e.getMessage());
        }
    }
    
    /**
     * Create a signed transaction
     * 
     * POST /ksm/createSignedTransaction
     * Body: {
     *   "from": "vietcombank",
     *   "to": "vietinbank",
     *   "amount": 1000000,
     *   "description": "Transfer"
     * }
     */
    @PostMapping("/createSignedTransaction")
    public Map<String, Object> createSignedTransaction(@RequestBody Map<String, Object> request) {
        try {
            String from = (String) request.get("from");
            String to = (String) request.get("to");
            double amount = ((Number) request.get("amount")).doubleValue();
            String description = (String) request.get("description");
            
            if (from == null || to == null) {
                return createErrorResponse("from and to are required");
            }
            
            System.out.println("[KSM] Creating signed transaction: " + from + " → " + to);
            
            SignedTransaction tx = pqcService.createSignedTransaction(from, to, amount, description);
            
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("transaction", Map.of(
                "from", tx.getFrom(),
                "to", tx.getTo(),
                "amount", tx.getAmount(),
                "description", tx.getDescription(),
                "timestamp", tx.getTimestamp()
            ));
            response.put("signature", Base64.getEncoder().encodeToString(tx.getSignature().getSignature()));
            response.put("algorithm", tx.getAlgorithm());
            response.put("message", "Signed transaction created successfully");
            
            System.out.println("[KSM] ✓ Signed transaction created");
            return response;
            
        } catch (Exception e) {
            System.err.println("[KSM] Error creating signed transaction: " + e.getMessage());
            return createErrorResponse("Transaction creation failed: " + e.getMessage());
        }
    }
    
    /**
     * Get public key for an entity
     * 
     * GET /ksm/publicKey/{entityId}
     */
    @GetMapping("/publicKey/{entityId}")
    public Map<String, Object> getPublicKey(@PathVariable String entityId) {
        try {
            PQCKeyPair keyPair = pqcService.getKeyPairForEntity(entityId);
            
            if (keyPair == null) {
                return createErrorResponse("Key pair not found for entity: " + entityId);
            }
            
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("entityId", entityId);
            response.put("publicKey", Base64.getEncoder().encodeToString(keyPair.getPublicKey()));
            response.put("algorithm", keyPair.getAlgorithm());
            response.put("publicKeySize", keyPair.getPublicKey().length);
            
            return response;
            
        } catch (Exception e) {
            return createErrorResponse("Failed to get public key: " + e.getMessage());
        }
    }
    
    /**
     * List all entities with keys
     * 
     * GET /ksm/entities
     */
    @GetMapping("/entities")
    public Map<String, Object> listEntities() {
        try {
            String[] entities = pqcService.listEntities();
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("entities", entities);
            response.put("count", entities.length);
            return response;
        } catch (Exception e) {
            return createErrorResponse("Failed to list entities: " + e.getMessage());
        }
    }
    
    /**
     * Delete key pair for entity
     * DELETE /ksm/deleteKey/{entityId}
     */
    @DeleteMapping("/deleteKey/{entityId}")
    public Map<String, Object> deleteKey(@PathVariable String entityId) {
        try {
            boolean deleted = pqcService.deleteKeyPair(entityId);
            Map<String, Object> response = new HashMap<>();
            response.put("success", deleted);
            response.put("entityId", entityId);
            response.put("message", deleted ? "Key deleted successfully" : "Key not found");
            return response;
        } catch (Exception e) {
            return createErrorResponse("Failed to delete key: " + e.getMessage());
        }
    }
    
    /**
     * Get storage statistics
     * GET /ksm/storage/stats
     */
    @GetMapping("/storage/stats")
    public Map<String, Object> getStorageStats() {
        try {
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.putAll(pqcService.getStorageStats());
            return response;
        } catch (Exception e) {
            return createErrorResponse("Failed to get storage stats: " + e.getMessage());
        }
    }
    
    // Helper methods
    
    private Map<String, Object> createErrorResponse(String message) {
        Map<String, Object> error = new HashMap<>();
        error.put("success", false);
        error.put("error", message);
        error.put("timestamp", System.currentTimeMillis());
        return error;
    }
}

