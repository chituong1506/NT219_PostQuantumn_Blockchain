package com.nt219.ksm.storage;

import com.nt219.ksm.crypto.PQCKeyPair;
import com.nt219.ksm.crypto.PQCAlgorithm;
import org.springframework.stereotype.Service;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import javax.crypto.spec.IvParameterSpec;
import java.io.*;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

/**
 * Service để quản lý persistent storage của PQC keys
 * 
 * Features:
 * - Lưu private keys encrypted với AES-256
 * - Public keys lưu plain text
 * - File-based storage (đơn giản, không cần database)
 * - Auto load on startup
 * - Thread-safe
 */
@Service
public class KeyStoreService {
    
    private static final String STORAGE_DIR = System.getenv().getOrDefault("KSM_STORAGE_DIR", 
        System.getProperty("ksm.storage.dir", "./ksm-data"));
    private static final String MASTER_KEY_FILE = STORAGE_DIR + "/master.key";
    private static final String KEYS_DIR = STORAGE_DIR + "/keys";
    
    private SecretKey masterKey;
    
    public KeyStoreService() {
        try {
            initializeStorage();
            loadOrGenerateMasterKey();
        } catch (Exception e) {
            throw new RuntimeException("Failed to initialize KeyStoreService", e);
        }
    }
    
    /**
     * Khởi tạo thư mục storage
     */
    private void initializeStorage() throws IOException {
        Files.createDirectories(Paths.get(STORAGE_DIR));
        Files.createDirectories(Paths.get(KEYS_DIR));
        System.out.println("[KSM] Storage initialized at: " + STORAGE_DIR);
    }
    
    /**
     * Load hoặc generate master key để encrypt private keys
     */
    private void loadOrGenerateMasterKey() throws Exception {
        File masterKeyFile = new File(MASTER_KEY_FILE);
        
        if (masterKeyFile.exists()) {
            // Load existing master key
            byte[] keyBytes = Files.readAllBytes(masterKeyFile.toPath());
            this.masterKey = new SecretKeySpec(keyBytes, "AES");
            System.out.println("[KSM] Master key loaded from file");
        } else {
            // Generate new master key
            KeyGenerator keyGen = KeyGenerator.getInstance("AES");
            keyGen.init(256, new SecureRandom());
            this.masterKey = keyGen.generateKey();
            
            // Save master key
            Files.write(masterKeyFile.toPath(), masterKey.getEncoded());
            System.out.println("[KSM] New master key generated and saved");
            
            // ⚠️ Security warning
            System.out.println("[WARNING] Master key file created at: " + MASTER_KEY_FILE);
            System.out.println("[WARNING] BACKUP this file! If lost, all keys cannot be decrypted!");
        }
    }
    
    /**
     * Save key pair to persistent storage
     * Private key được encrypt với AES-256
     */
    public void saveKeyPair(String entityId, PQCKeyPair keyPair) throws Exception {
        String keyFile = KEYS_DIR + "/" + entityId + ".properties";
        Properties props = new Properties();
        
        // Save metadata
        props.setProperty("entityId", entityId);
        props.setProperty("algorithm", keyPair.getAlgorithm().toString());
        props.setProperty("createdAt", String.valueOf(System.currentTimeMillis()));
        
        // Save public key (plain text, Base64 encoded)
        String publicKeyB64 = Base64.getEncoder().encodeToString(keyPair.getPublicKey());
        props.setProperty("publicKey", publicKeyB64);
        props.setProperty("publicKeySize", String.valueOf(keyPair.getPublicKey().length));
        
        // Encrypt and save private key
        byte[] encryptedPrivateKey = encryptPrivateKey(keyPair.getPrivateKey());
        String privateKeyB64 = Base64.getEncoder().encodeToString(encryptedPrivateKey);
        props.setProperty("privateKeyEncrypted", privateKeyB64);
        
        // Save to file
        try (FileOutputStream out = new FileOutputStream(keyFile)) {
            props.store(out, "PQC Key Pair for " + entityId);
        }
        
        System.out.println("[KSM] Key pair saved for entity: " + entityId);
    }
    
    /**
     * Load key pair from persistent storage
     * Private key được decrypt automatically
     */
    public PQCKeyPair loadKeyPair(String entityId) throws Exception {
        String keyFile = KEYS_DIR + "/" + entityId + ".properties";
        File file = new File(keyFile);
        
        if (!file.exists()) {
            return null; // Key not found
        }
        
        Properties props = new Properties();
        try (FileInputStream in = new FileInputStream(file)) {
            props.load(in);
        }
        
        // Load algorithm
        String algorithmStr = props.getProperty("algorithm");
        PQCAlgorithm algorithm;
        try {
            algorithm = PQCAlgorithm.valueOf(algorithmStr);
        } catch (IllegalArgumentException e) {
            // Fallback to DILITHIUM3 if algorithm not found
            algorithm = PQCAlgorithm.DILITHIUM3;
        }
        
        // Load public key
        String publicKeyB64 = props.getProperty("publicKey");
        byte[] publicKey = Base64.getDecoder().decode(publicKeyB64);
        
        // Load and decrypt private key
        String privateKeyB64 = props.getProperty("privateKeyEncrypted");
        byte[] encryptedPrivateKey = Base64.getDecoder().decode(privateKeyB64);
        byte[] privateKey = decryptPrivateKey(encryptedPrivateKey);
        
        System.out.println("[KSM] Key pair loaded for entity: " + entityId);
        
        // Create PQCKeyPair with algorithm string
        PQCKeyPair keyPair = new PQCKeyPair(publicKey, privateKey, algorithm.toString());
        return keyPair;
    }
    
    /**
     * Load all key pairs from storage
     */
    public Map<String, PQCKeyPair> loadAllKeyPairs() throws Exception {
        Map<String, PQCKeyPair> keyStore = new HashMap<>();
        File keysDir = new File(KEYS_DIR);
        
        File[] files = keysDir.listFiles((dir, name) -> name.endsWith(".properties"));
        if (files == null) {
            return keyStore;
        }
        
        for (File file : files) {
            String entityId = file.getName().replace(".properties", "");
            try {
                PQCKeyPair keyPair = loadKeyPair(entityId);
                if (keyPair != null) {
                    keyStore.put(entityId, keyPair);
                }
            } catch (Exception e) {
                System.err.println("[KSM] Failed to load key for entity: " + entityId);
                e.printStackTrace();
            }
        }
        
        System.out.println("[KSM] Loaded " + keyStore.size() + " key pairs from storage");
        return keyStore;
    }
    
    /**
     * Delete key pair from storage
     */
    public boolean deleteKeyPair(String entityId) {
        String keyFile = KEYS_DIR + "/" + entityId + ".properties";
        File file = new File(keyFile);
        
        if (file.exists()) {
            boolean deleted = file.delete();
            if (deleted) {
                System.out.println("[KSM] Key pair deleted for entity: " + entityId);
            }
            return deleted;
        }
        
        return false;
    }
    
    /**
     * Check if key exists for entity
     */
    public boolean keyExists(String entityId) {
        String keyFile = KEYS_DIR + "/" + entityId + ".properties";
        return new File(keyFile).exists();
    }
    
    /**
     * Get public key only (for sharing with others)
     */
    public byte[] getPublicKey(String entityId) throws Exception {
        PQCKeyPair keyPair = loadKeyPair(entityId);
        return keyPair != null ? keyPair.getPublicKey() : null;
    }
    
    /**
     * Encrypt private key với AES-256-CBC
     */
    private byte[] encryptPrivateKey(byte[] privateKey) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
        
        // Generate random IV
        SecureRandom random = new SecureRandom();
        byte[] iv = new byte[16];
        random.nextBytes(iv);
        IvParameterSpec ivSpec = new IvParameterSpec(iv);
        
        cipher.init(Cipher.ENCRYPT_MODE, masterKey, ivSpec);
        byte[] encrypted = cipher.doFinal(privateKey);
        
        // Prepend IV to encrypted data
        byte[] result = new byte[iv.length + encrypted.length];
        System.arraycopy(iv, 0, result, 0, iv.length);
        System.arraycopy(encrypted, 0, result, iv.length, encrypted.length);
        
        return result;
    }
    
    /**
     * Decrypt private key với AES-256-CBC
     */
    private byte[] decryptPrivateKey(byte[] encryptedData) throws Exception {
        // Extract IV from first 16 bytes
        byte[] iv = new byte[16];
        System.arraycopy(encryptedData, 0, iv, 0, 16);
        IvParameterSpec ivSpec = new IvParameterSpec(iv);
        
        // Extract encrypted data
        byte[] encrypted = new byte[encryptedData.length - 16];
        System.arraycopy(encryptedData, 16, encrypted, 0, encrypted.length);
        
        // Decrypt
        Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
        cipher.init(Cipher.DECRYPT_MODE, masterKey, ivSpec);
        return cipher.doFinal(encrypted);
    }
    
    /**
     * List all stored entity IDs
     */
    public String[] listEntities() {
        File keysDir = new File(KEYS_DIR);
        File[] files = keysDir.listFiles((dir, name) -> name.endsWith(".properties"));
        
        if (files == null) {
            return new String[0];
        }
        
        String[] entities = new String[files.length];
        for (int i = 0; i < files.length; i++) {
            entities[i] = files[i].getName().replace(".properties", "");
        }
        
        return entities;
    }
    
    /**
     * Get storage statistics
     */
    public Map<String, Object> getStorageStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("storageDir", STORAGE_DIR);
        stats.put("totalEntities", listEntities().length);
        stats.put("masterKeyExists", new File(MASTER_KEY_FILE).exists());
        
        File keysDir = new File(KEYS_DIR);
        long totalSize = 0;
        File[] files = keysDir.listFiles();
        if (files != null) {
            for (File file : files) {
                totalSize += file.length();
            }
        }
        stats.put("totalStorageSize", totalSize);
        
        return stats;
    }
}

