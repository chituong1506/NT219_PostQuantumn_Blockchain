// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @title BalanceVerifier
 * @dev Smart contract để verify ZKP proof cho balance > amount
 * 
 * Chức năng:
 * - Verify balance proof từ ZKP prover
 * - Lưu trữ verified proofs
 * - Tích hợp với InterbankTransfer contract
 */
contract BalanceVerifier {
    
    // Mapping từ proof hash đến verification status
    mapping(bytes32 => bool) public verifiedProofs;
    
    // Struct cho balance proof
    struct BalanceProof {
        uint256 amount;              // Số tiền cần chuyển (public)
        bytes32 commitmentHash;      // Hash của balance commitment
        bytes proofBytes;             // Proof bytes từ prover
        address userAddress;          // Address của user
    }
    
    // Events
    event ProofVerified(
        bytes32 indexed proofHash,
        address indexed userAddress,
        uint256 amount,
        bytes32 commitmentHash
    );
    
    event ProofRejected(
        bytes32 indexed proofHash,
        string reason
    );
    
    // Owner
    address public owner;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Verify balance proof
     * @param proof Balance proof từ prover
     * @return verified True nếu proof hợp lệ
     */
    function verifyProof(BalanceProof memory proof)
        external
        returns (bool verified)
    {
        // Check if already verified
        bytes32 proofHash = keccak256(abi.encodePacked(
            proof.amount,
            proof.commitmentHash,
            proof.proofBytes,
            proof.userAddress
        ));
        
        if (verifiedProofs[proofHash]) {
            emit ProofRejected(proofHash, "Proof already verified");
            return false;
        }
        
        // Basic validation
        require(proof.amount > 0, "Amount must be greater than 0");
        require(proof.userAddress != address(0), "Invalid user address");
        require(proof.proofBytes.length > 0, "Empty proof");
        
        // Verify proof
        // Trong implementation đơn giản này, chúng ta verify:
        // 1. Proof bytes không rỗng
        // 2. Commitment hash hợp lệ
        // 3. Trong production, sẽ có full STARK verification ở đây
        
        bool isValid = _verifyBalanceProof(proof);
        
        if (isValid) {
            verifiedProofs[proofHash] = true;
            emit ProofVerified(
                proofHash,
                proof.userAddress,
                proof.amount,
                proof.commitmentHash
            );
            return true;
        } else {
            emit ProofRejected(proofHash, "Invalid proof");
            return false;
        }
    }
    
    /**
     * @dev Internal function để verify balance proof
     * @notice Trong production, đây sẽ là full STARK verification
     * @param proof Balance proof
     * @return isValid True nếu proof hợp lệ
     */
    function _verifyBalanceProof(BalanceProof memory proof) 
        internal 
        pure 
        returns (bool isValid) 
    {
        // Simplified verification:
        // 1. Check proof size (minimum size)
        if (proof.proofBytes.length < 32) {
            return false;
        }
        
        // 2. Verify commitment hash format
        if (proof.commitmentHash == bytes32(0)) {
            return false;
        }
        
        // 3. Trong production: Full STARK verification sẽ ở đây
        // - Verify FRI (Fast Reed-Solomon IOP)
        // - Check constraint polynomial
        // - Verify Merkle proofs
        // - Verify balance > amount constraint
        
        // Tạm thời accept nếu proof có format hợp lệ
        // Trong production, cần verify STARK proof đầy đủ
        return true;
    }
    
    /**
     * @dev Check if proof has been verified
     * @param proofHash Hash của proof
     * @return verified True nếu đã được verify
     */
    function isProofVerified(bytes32 proofHash) external view returns (bool) {
        return verifiedProofs[proofHash];
    }
    
    /**
     * @dev Get proof hash từ proof data
     * @param proof Balance proof
     * @return proofHash Hash của proof
     */
    function getProofHash(BalanceProof memory proof) 
        external 
        pure 
        returns (bytes32) 
    {
        return keccak256(abi.encodePacked(
            proof.amount,
            proof.commitmentHash,
            proof.proofBytes,
            proof.userAddress
        ));
    }
}

