package com.nt219.ksm.crypto;

import com.nt219.ksm.crypto.impl.DilithiumService;
import com.nt219.ksm.crypto.impl.KyberService;

/**
 * Factory class để tạo các service PQC tương ứng với từng thuật toán
 */
public class PQCCryptoFactory {
    
    /**
     * Tạo service PQC dựa trên thuật toán được chọn
     * @param algorithm Thuật toán PQC
     * @return Service tương ứng
     * @throws IllegalArgumentException Nếu thuật toán không được hỗ trợ
     */
    public static IPQCCryptoService createService(PQCAlgorithm algorithm) {
        String algorithmName = algorithm.name();
        
        if (algorithmName.startsWith("DILITHIUM")) {
            return new DilithiumService();
        } else if (algorithmName.startsWith("KYBER")) {
            return new KyberService();
        } else if (algorithmName.startsWith("SPHINCS")) {
            // TODO: Implement SPHINCS+ service
            throw new UnsupportedOperationException("SPHINCS+ is not yet implemented");
        } else {
            throw new IllegalArgumentException("Unsupported PQC algorithm: " + algorithm);
        }
    }
    
    /**
     * Kiểm tra xem thuật toán có phải là thuật toán chữ ký số không
     */
    public static boolean isSignatureAlgorithm(PQCAlgorithm algorithm) {
        return algorithm.name().startsWith("DILITHIUM") || 
               algorithm.name().startsWith("SPHINCS");
    }
    
    /**
     * Kiểm tra xem thuật toán có phải là thuật toán mã hóa không
     */
    public static boolean isEncryptionAlgorithm(PQCAlgorithm algorithm) {
        return algorithm.name().startsWith("KYBER");
    }
}

