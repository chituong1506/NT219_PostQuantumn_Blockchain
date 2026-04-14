package com.nt219.ksm.process;

import com.nt219.ksm.crypto.PQCSignature;

/**
 * Lớp đại diện cho một transaction đã được ký bằng PQC
 */
public class SignedTransaction {
    private final String fromEntityId;
    private final String toEntityId;
    private final double amount;
    private final String description;
    private final String transactionData;
    private final PQCSignature signature;
    private final long timestamp;
    
    public SignedTransaction(
            String fromEntityId,
            String toEntityId,
            double amount,
            String description,
            String transactionData,
            PQCSignature signature,
            long timestamp) {
        this.fromEntityId = fromEntityId;
        this.toEntityId = toEntityId;
        this.amount = amount;
        this.description = description;
        this.transactionData = transactionData;
        this.signature = signature;
        this.timestamp = timestamp;
    }
    
    // Getters
    public String getFromEntityId() { return fromEntityId; }
    public String getToEntityId() { return toEntityId; }
    public double getAmount() { return amount; }
    public String getDescription() { return description; }
    public String getTransactionData() { return transactionData; }
    public PQCSignature getSignature() { return signature; }
    public long getTimestamp() { return timestamp; }
    
    // Alias methods for compatibility
    public String getFrom() { return fromEntityId; }
    public String getTo() { return toEntityId; }
    public String getAlgorithm() { return signature != null ? signature.getAlgorithm() : null; }
    
    @Override
    public String toString() {
        return String.format(
            "SignedTransaction{from=%s, to=%s, amount=%.2f, desc=%s, timestamp=%d, signature=%s}",
            fromEntityId, toEntityId, amount, description, timestamp, 
            signature != null ? signature.getSignatureHex().substring(0, 32) + "..." : "null"
        );
    }
}

