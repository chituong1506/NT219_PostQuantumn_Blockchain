package com.nt219.ksm.process;

import com.nt219.ksm.crypto.*;
import com.nt219.ksm.storage.KeyStoreService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

/**
 * Service để tích hợp PQC vào các process của hệ thống
 * 
 * Lớp này cung cấp các phương thức tiện ích để:
 * - Ký và xác thực transactions
 * - Mã hóa và giải mã dữ liệu nhạy cảm
 * - Quản lý khóa PQC với persistent storage
 * 
 * Features:
 * - ✅ Persistent key storage (encrypted private keys)
 * - ✅ Auto-load keys on startup
 * - ✅ Thread-safe operations
 * - ✅ In-memory cache for performance
 */
@Service
public class PQCProcessService {
    
    private final Map<String, PQCKeyPair> keyCache; // In-memory cache for performance
    private final PQCAlgorithm defaultSignatureAlgorithm;
    private final PQCAlgorithm defaultEncryptionAlgorithm;
    private final KeyStoreService keyStoreService;
    
    @Autowired
    public PQCProcessService(KeyStoreService keyStoreService) {
        this.keyStoreService = keyStoreService;
        this.keyCache = new HashMap<>();
        this.defaultSignatureAlgorithm = PQCAlgorithm.DILITHIUM3;
        this.defaultEncryptionAlgorithm = PQCAlgorithm.KYBER768;
        
        // Load existing keys from persistent storage
        loadExistingKeys();
    }
    
    /**
     * Load all existing keys from persistent storage into cache
     */
    private void loadExistingKeys() {
        try {
            Map<String, PQCKeyPair> storedKeys = keyStoreService.loadAllKeyPairs();
            keyCache.putAll(storedKeys);
            System.out.println("[PQCProcessService] Loaded " + storedKeys.size() + " keys from storage");
        } catch (Exception e) {
            System.err.println("[PQCProcessService] Failed to load keys from storage: " + e.getMessage());
            e.printStackTrace();
        }
    }
    
    /**
     * Tạo cặp khóa cho một user/entity
     * ✅ Automatically saves to persistent storage
     * 
     * @param entityId ID của entity (ví dụ: user ID, bank code)
     * @return Cặp khóa được tạo
     */
    public PQCKeyPair generateKeyPairForEntity(String entityId) throws Exception {
        // Check if key already exists
        if (keyStoreService.keyExists(entityId)) {
            System.out.println("[PQCProcessService] Key already exists for: " + entityId);
            return getKeyPair(entityId);
        }
        
        // Generate new key pair
        IPQCCryptoService service = PQCCryptoFactory.createService(defaultSignatureAlgorithm);
        PQCKeyPair keyPair = service.generateKeyPair(defaultSignatureAlgorithm);
        
        // Save to persistent storage (encrypted)
        keyStoreService.saveKeyPair(entityId, keyPair);
        
        // Cache in memory
        keyCache.put(entityId, keyPair);
        
        System.out.println("[PQCProcessService] Generated and saved key pair for: " + entityId);
        return keyPair;
    }
    
    /**
     * Lấy cặp khóa của một entity
     * ✅ Tries cache first, then loads from storage if needed
     */
    public PQCKeyPair getKeyPair(String entityId) {
        // Try cache first
        PQCKeyPair cached = keyCache.get(entityId);
        if (cached != null) {
            return cached;
        }
        
        // Load from persistent storage
        try {
            PQCKeyPair keyPair = keyStoreService.loadKeyPair(entityId);
            if (keyPair != null) {
                keyCache.put(entityId, keyPair); // Cache it
                System.out.println("[PQCProcessService] Loaded key from storage for: " + entityId);
            }
            return keyPair;
        } catch (Exception e) {
            System.err.println("[PQCProcessService] Failed to load key for " + entityId + ": " + e.getMessage());
            return null;
        }
    }
    
    /**
     * Alias for getKeyPair() - for compatibility
     */
    public PQCKeyPair getKeyPairForEntity(String entityId) {
        return getKeyPair(entityId);
    }
    
    /**
     * Delete key pair for entity
     * ✅ Removes from both cache and persistent storage
     */
    public boolean deleteKeyPair(String entityId) {
        keyCache.remove(entityId);
        return keyStoreService.deleteKeyPair(entityId);
    }
    
    /**
     * Get public key only (for sharing)
     */
    public byte[] getPublicKey(String entityId) throws Exception {
        PQCKeyPair keyPair = getKeyPair(entityId);
        return keyPair != null ? keyPair.getPublicKey() : null;
    }
    
    /**
     * List all entities with stored keys
     */
    public String[] listEntities() {
        return keyStoreService.listEntities();
    }
    
    /**
     * Get storage statistics
     */
    public Map<String, Object> getStorageStats() {
        Map<String, Object> stats = keyStoreService.getStorageStats();
        stats.put("cachedKeys", keyCache.size());
        return stats;
    }
    
    /**
     * Ký một transaction hoặc message
     * ✅ Uses private key from persistent storage
     * 
     * @param entityId ID của entity thực hiện ký
     * @param message Dữ liệu cần ký
     * @return Chữ ký số
     */
    public PQCSignature signTransaction(String entityId, String message) throws Exception {
        PQCKeyPair keyPair = getKeyPair(entityId); // Auto-loads from storage if needed
        if (keyPair == null) {
            throw new IllegalArgumentException("Key pair not found for entity: " + entityId + ". Generate key first!");
        }
        
        IPQCCryptoService service = PQCCryptoFactory.createService(defaultSignatureAlgorithm);
        byte[] messageBytes = message.getBytes(StandardCharsets.UTF_8);
        return service.sign(messageBytes, keyPair.getPrivateKey(), defaultSignatureAlgorithm);
    }
    
    /**
     * Xác thực chữ ký của transaction
     * @param entityId ID của entity đã ký
     * @param message Dữ liệu gốc
     * @param signature Chữ ký số
     * @return true nếu chữ ký hợp lệ
     */
    public boolean verifyTransaction(String entityId, String message, PQCSignature signature) throws Exception {
        PQCKeyPair keyPair = getKeyPair(entityId); // Auto-loads from storage if needed
        if (keyPair == null) {
            throw new IllegalArgumentException("Key pair not found for entity: " + entityId);
        }
        
        IPQCCryptoService service = PQCCryptoFactory.createService(defaultSignatureAlgorithm);
        byte[] messageBytes = message.getBytes(StandardCharsets.UTF_8);
        return service.verify(messageBytes, signature, keyPair.getPublicKey(), defaultSignatureAlgorithm);
    }
    
    /**
     * Mã hóa dữ liệu nhạy cảm
     * @param entityId ID của entity nhận (có public key)
     * @param plaintext Dữ liệu cần mã hóa
     * @return Dữ liệu đã mã hóa
     */
    public byte[] encryptSensitiveData(String entityId, String plaintext) throws Exception {
        PQCKeyPair keyPair = getKeyPair(entityId); // Auto-loads from storage if needed
        if (keyPair == null) {
            throw new IllegalArgumentException("Key pair not found for entity: " + entityId);
        }
        
        IPQCCryptoService service = PQCCryptoFactory.createService(defaultEncryptionAlgorithm);
        byte[] plaintextBytes = plaintext.getBytes(StandardCharsets.UTF_8);
        return service.encrypt(plaintextBytes, keyPair.getPublicKey(), defaultEncryptionAlgorithm);
    }
    
    /**
     * Giải mã dữ liệu nhạy cảm
     * ✅ Uses private key from persistent storage (auto-decrypted)
     * 
     * @param entityId ID của entity sở hữu private key
     * @param ciphertext Dữ liệu đã mã hóa
     * @return Dữ liệu đã giải mã
     */
    public String decryptSensitiveData(String entityId, byte[] ciphertext) throws Exception {
        PQCKeyPair keyPair = getKeyPair(entityId); // Auto-loads from storage if needed
        if (keyPair == null) {
            throw new IllegalArgumentException("Key pair not found for entity: " + entityId);
        }
        
        IPQCCryptoService service = PQCCryptoFactory.createService(defaultEncryptionAlgorithm);
        byte[] decrypted = service.decrypt(ciphertext, keyPair.getPrivateKey(), defaultEncryptionAlgorithm);
        return new String(decrypted, StandardCharsets.UTF_8);
    }
    
    /**
     * Tạo transaction object với chữ ký PQC
     * @param fromEntityId ID của entity gửi
     * @param toEntityId ID của entity nhận
     * @param amount Số tiền
     * @param description Mô tả
     * @return Transaction object với chữ ký
     */
    public SignedTransaction createSignedTransaction(
            String fromEntityId, 
            String toEntityId, 
            double amount, 
            String description) throws Exception {
        
        // Tạo transaction data
        String transactionData = String.format(
            "FROM:%s|TO:%s|AMOUNT:%.2f|DESC:%s|TIMESTAMP:%d",
            fromEntityId, toEntityId, amount, description, System.currentTimeMillis()
        );
        
        // Ký transaction
        PQCSignature signature = signTransaction(fromEntityId, transactionData);
        
        return new SignedTransaction(
            fromEntityId,
            toEntityId,
            amount,
            description,
            transactionData,
            signature,
            System.currentTimeMillis()
        );
    }
    
    /**
     * Xác thực signed transaction
     */
    public boolean verifySignedTransaction(SignedTransaction transaction) throws Exception {
        return verifyTransaction(
            transaction.getFromEntityId(),
            transaction.getTransactionData(),
            transaction.getSignature()
        );
    }
}

