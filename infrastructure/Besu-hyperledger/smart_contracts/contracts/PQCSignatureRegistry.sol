// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @title PQCSignatureRegistry
 * @dev Contract riêng để lưu trữ PQC signature on-chain cho từng transaction.
 *      Mục tiêu: giảm kích thước bytecode của InterbankTransfer (tránh vượt EIP-170)
 *      nhưng vẫn đảm bảo requirement: lưu PQC signature / hash on-chain.
 */
contract PQCSignatureRegistry {
    address public owner;
    address public interbankContract;

    struct PQCData {
        bytes signature;
        string algorithm;
        bytes32 hash;
        bool exists;
    }

    mapping(uint256 => PQCData) private pqcByTxId;

    event PQCSignatureStored(
        uint256 indexed transactionId,
        bytes32 signatureHash,
        string algorithm,
        uint256 signatureSize
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyInterbank() {
        require(msg.sender == interbankContract, "Only Interbank contract");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Set địa chỉ InterbankTransfer contract (chỉ owner)
     */
    function setInterbankContract(address _interbank) external onlyOwner {
        require(_interbank != address(0), "Invalid address");
        interbankContract = _interbank;
    }

    /**
     * @dev Lưu PQC signature cho một transaction (chỉ được gọi từ InterbankTransfer)
     * @param txId Transaction ID trong InterbankTransfer
     * @param pqcSignature PQC signature (bytes)
     * @param algorithm Tên thuật toán PQC (vd: "Dilithium3")
     */
    function storePQCSignature(
        uint256 txId,
        bytes calldata pqcSignature,
        string calldata algorithm
    ) external onlyInterbank {
        require(txId > 0, "Invalid txId");
        require(pqcSignature.length > 0, "Empty signature");
        require(bytes(algorithm).length > 0, "Empty algorithm");

        bytes32 signatureHash = keccak256(abi.encodePacked(pqcSignature, algorithm));

        pqcByTxId[txId] = PQCData({
            signature: pqcSignature,
            algorithm: algorithm,
            hash: signatureHash,
            exists: true
        });

        emit PQCSignatureStored(txId, signatureHash, algorithm, pqcSignature.length);
    }

    /**
     * @dev Lấy hash của PQC signature cho một transaction
     */
    function getPQCSignatureHash(uint256 txId) external view returns (bytes32) {
        require(pqcByTxId[txId].exists, "No PQC signature for tx");
        return pqcByTxId[txId].hash;
    }

    /**
     * @dev Lấy full PQC signature + algorithm + hash cho một transaction
     */
    function getPQCSignature(uint256 txId)
        external
        view
        returns (
            bytes memory signature,
            string memory algorithm,
            bytes32 signatureHash
        )
    {
        require(pqcByTxId[txId].exists, "No PQC signature for tx");
        PQCData memory data = pqcByTxId[txId];
        return (data.signature, data.algorithm, data.hash);
    }

    /**
     * @dev Kiểm tra transaction có PQC signature hay không
     */
    function transactionHasPQCSignature(uint256 txId) external view returns (bool) {
        return pqcByTxId[txId].exists;
    }
}


