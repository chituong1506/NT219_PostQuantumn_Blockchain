package com.nt219.ksm.crypto;

/**
 * Enum định nghĩa các thuật toán PQC được hỗ trợ
 */
public enum PQCAlgorithm {
    /**
     * Dilithium - Thuật toán chữ ký số dựa trên lattice
     * Được NIST chọn làm chuẩn chữ ký số hậu lượng tử
     */
    DILITHIUM2("Dilithium2"),
    DILITHIUM3("Dilithium3"),
    DILITHIUM5("Dilithium5"),

    /**
     * Kyber - Thuật toán mã hóa khóa công khai dựa trên lattice
     * Được NIST chọn làm chuẩn mã hóa khóa công khai hậu lượng tử
     */
    KYBER512("Kyber512"),
    KYBER768("Kyber768"),
    KYBER1024("Kyber1024"),

    /**
     * SPHINCS+ - Thuật toán chữ ký số dựa trên hash
     * Được NIST chọn làm thuật toán dự phòng
     */
    SPHINCS_PLUS_128F("SPHINCS+-128f"),
    SPHINCS_PLUS_192F("SPHINCS+-192f"),
    SPHINCS_PLUS_256F("SPHINCS+-256f");

    private final String name;

    PQCAlgorithm(String name) {
        this.name = name;
    }

    public String getName() {
        return name;
    }

    @Override
    public String toString() {
        return name;
    }
}

