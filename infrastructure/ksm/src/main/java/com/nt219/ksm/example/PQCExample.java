package com.nt219.ksm.example;

import com.nt219.ksm.crypto.*;
import com.nt219.ksm.process.PQCProcessService;
import com.nt219.ksm.process.SignedTransaction;

/**
 * Ví dụ sử dụng PQC trong các tình huống thực tế
 */
public class PQCExample {
    
    public static void main(String[] args) {
        try {
            // Ví dụ 1: Tạo khóa và ký/xác thực message
            example1_SignAndVerify();
            
            // Ví dụ 2: Mã hóa và giải mã dữ liệu
            example2_EncryptAndDecrypt();
            
            // Ví dụ 3: Tạo và xác thực transaction
            example3_SignedTransaction();
            
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
        }
    }
    
    /**
     * Ví dụ 1: Ký và xác thực message bằng Dilithium
     */
    public static void example1_SignAndVerify() throws Exception {
        System.out.println("\n=== Ví dụ 1: Ký và xác thực message ===");
        
        // Tạo service Dilithium
        IPQCCryptoService service = PQCCryptoFactory.createService(PQCAlgorithm.DILITHIUM3);
        
        // Tạo cặp khóa
        System.out.println("Đang tạo cặp khóa Dilithium3...");
        PQCKeyPair keyPair = service.generateKeyPair(PQCAlgorithm.DILITHIUM3);
        System.out.println("Public Key (hex): " + keyPair.getPublicKeyHex().substring(0, 64) + "...");
        System.out.println("Private Key (hex): " + keyPair.getPrivateKeyHex().substring(0, 64) + "...");
        
        // Message cần ký
        String message = "Đây là một transaction quan trọng từ Vietcombank";
        byte[] messageBytes = message.getBytes("UTF-8");
        
        // Ký message
        System.out.println("\nĐang ký message...");
        PQCSignature signature = service.sign(messageBytes, keyPair.getPrivateKey(), PQCAlgorithm.DILITHIUM3);
        System.out.println("Signature (hex): " + signature.getSignatureHex().substring(0, 64) + "...");
        
        // Xác thực chữ ký
        System.out.println("\nĐang xác thực chữ ký...");
        boolean isValid = service.verify(messageBytes, signature, keyPair.getPublicKey(), PQCAlgorithm.DILITHIUM3);
        System.out.println("Chữ ký hợp lệ: " + isValid);
    }
    
    /**
     * Ví dụ 2: Mã hóa và giải mã bằng Kyber
     */
    public static void example2_EncryptAndDecrypt() throws Exception {
        System.out.println("\n=== Ví dụ 2: Mã hóa và giải mã dữ liệu ===");
        
        // Tạo service Kyber
        IPQCCryptoService service = PQCCryptoFactory.createService(PQCAlgorithm.KYBER768);
        
        // Tạo cặp khóa
        System.out.println("Đang tạo cặp khóa Kyber768...");
        PQCKeyPair keyPair = service.generateKeyPair(PQCAlgorithm.KYBER768);
        
        // Dữ liệu cần mã hóa
        String plaintext = "Số tài khoản: 1234567890, Số tiền: 1,000,000 VND";
        byte[] plaintextBytes = plaintext.getBytes("UTF-8");
        System.out.println("Plaintext: " + plaintext);
        
        // Mã hóa
        System.out.println("\nĐang mã hóa...");
        byte[] ciphertext = service.encrypt(plaintextBytes, keyPair.getPublicKey(), PQCAlgorithm.KYBER768);
        System.out.println("Ciphertext length: " + ciphertext.length + " bytes");
        
        // Giải mã
        System.out.println("\nĐang giải mã...");
        byte[] decrypted = service.decrypt(ciphertext, keyPair.getPrivateKey(), PQCAlgorithm.KYBER768);
        String decryptedText = new String(decrypted, "UTF-8");
        System.out.println("Decrypted: " + decryptedText);
        System.out.println("Mã hóa/giải mã thành công: " + plaintext.equals(decryptedText));
    }
    
    /**
     * Ví dụ 3: Tạo và xác thực transaction với PQCProcessService
     */
    public static void example3_SignedTransaction() throws Exception {
        System.out.println("\n=== Ví dụ 3: Transaction với chữ ký PQC ===");
        
        // Tạo service process
        // Note: In production, PQCProcessService is injected by Spring
        // For this example, we create it manually with a KeyStoreService
        com.nt219.ksm.storage.KeyStoreService keyStoreService = new com.nt219.ksm.storage.KeyStoreService();
        PQCProcessService processService = new PQCProcessService(keyStoreService);
        
        // Tạo khóa cho các ngân hàng
        System.out.println("Đang tạo khóa cho các ngân hàng...");
        processService.generateKeyPairForEntity("vietcombank");
        processService.generateKeyPairForEntity("vietinbank");
        processService.generateKeyPairForEntity("bidv");
        
        // Tạo transaction từ Vietcombank đến Vietinbank
        System.out.println("\nĐang tạo transaction...");
        SignedTransaction transaction = processService.createSignedTransaction(
            "vietcombank",
            "vietinbank",
            1000000.0,
            "Chuyển tiền liên ngân hàng"
        );
        
        System.out.println("Transaction: " + transaction);
        
        // Xác thực transaction
        System.out.println("\nĐang xác thực transaction...");
        boolean isValid = processService.verifySignedTransaction(transaction);
        System.out.println("Transaction hợp lệ: " + isValid);
    }
}

