package com.nt219.ksm.crypto;

/**
 * Interface định nghĩa các phương thức cơ bản cho mật mã hậu lượng tử
 */
public interface IPQCCryptoService {
    
    /**
     * Tạo cặp khóa (public key và private key)
     * @param algorithm Thuật toán PQC sử dụng
     * @return Cặp khóa được tạo
     * @throws Exception Nếu có lỗi trong quá trình tạo khóa
     */
    PQCKeyPair generateKeyPair(PQCAlgorithm algorithm) throws Exception;

    /**
     * Ký một message bằng private key
     * @param message Dữ liệu cần ký
     * @param privateKey Khóa bí mật
     * @param algorithm Thuật toán PQC sử dụng
     * @return Chữ ký số
     * @throws Exception Nếu có lỗi trong quá trình ký
     */
    PQCSignature sign(byte[] message, byte[] privateKey, PQCAlgorithm algorithm) throws Exception;

    /**
     * Xác thực chữ ký số
     * @param message Dữ liệu gốc
     * @param signature Chữ ký số
     * @param publicKey Khóa công khai
     * @param algorithm Thuật toán PQC sử dụng
     * @return true nếu chữ ký hợp lệ, false nếu không
     * @throws Exception Nếu có lỗi trong quá trình xác thực
     */
    boolean verify(byte[] message, PQCSignature signature, byte[] publicKey, PQCAlgorithm algorithm) throws Exception;

    /**
     * Mã hóa dữ liệu bằng public key (cho các thuật toán mã hóa như Kyber)
     * @param plaintext Dữ liệu cần mã hóa
     * @param publicKey Khóa công khai
     * @param algorithm Thuật toán PQC sử dụng
     * @return Dữ liệu đã mã hóa
     * @throws Exception Nếu có lỗi trong quá trình mã hóa
     */
    byte[] encrypt(byte[] plaintext, byte[] publicKey, PQCAlgorithm algorithm) throws Exception;

    /**
     * Giải mã dữ liệu bằng private key
     * @param ciphertext Dữ liệu đã mã hóa
     * @param privateKey Khóa bí mật
     * @param algorithm Thuật toán PQC sử dụng
     * @return Dữ liệu đã giải mã
     * @throws Exception Nếu có lỗi trong quá trình giải mã
     */
    byte[] decrypt(byte[] ciphertext, byte[] privateKey, PQCAlgorithm algorithm) throws Exception;
}

