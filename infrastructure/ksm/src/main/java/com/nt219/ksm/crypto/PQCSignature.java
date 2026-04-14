package com.nt219.ksm.crypto;

/**
 * Lớp đại diện cho chữ ký số trong mật mã hậu lượng tử
 */
public class PQCSignature {
    private final byte[] signature;
    private final String algorithm;

    public PQCSignature(byte[] signature, String algorithm) {
        this.signature = signature;
        this.algorithm = algorithm;
    }

    public byte[] getSignature() {
        return signature;
    }

    public String getAlgorithm() {
        return algorithm;
    }

    /**
     * Chuyển đổi chữ ký sang dạng hex string
     */
    public String getSignatureHex() {
        return bytesToHex(signature);
    }

    private String bytesToHex(byte[] bytes) {
        StringBuilder hex = new StringBuilder();
        for (byte b : bytes) {
            hex.append(String.format("%02x", b));
        }
        return hex.toString();
    }
}

