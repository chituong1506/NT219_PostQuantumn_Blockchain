package com.nt219.ksm.crypto;

/**
 * Lớp đại diện cho cặp khóa trong mật mã hậu lượng tử
 * Bao gồm khóa công khai (public key) và khóa bí mật (private key)
 */
public class PQCKeyPair {
    private final byte[] publicKey;
    private final byte[] privateKey;
    private final String algorithm;

    public PQCKeyPair(byte[] publicKey, byte[] privateKey, String algorithm) {
        this.publicKey = publicKey;
        this.privateKey = privateKey;
        this.algorithm = algorithm;
    }

    public byte[] getPublicKey() {
        return publicKey;
    }

    public byte[] getPrivateKey() {
        return privateKey;
    }

    public String getAlgorithm() {
        return algorithm;
    }

    /**
     * Chuyển đổi khóa công khai sang dạng hex string
     */
    public String getPublicKeyHex() {
        return bytesToHex(publicKey);
    }

    /**
     * Chuyển đổi khóa bí mật sang dạng hex string
     */
    public String getPrivateKeyHex() {
        return bytesToHex(privateKey);
    }

    private String bytesToHex(byte[] bytes) {
        StringBuilder hex = new StringBuilder();
        for (byte b : bytes) {
            hex.append(String.format("%02x", b));
        }
        return hex.toString();
    }
}

