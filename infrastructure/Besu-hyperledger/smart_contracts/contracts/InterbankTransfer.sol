// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @dev Interface for PKIRegistry contract
 */
interface IPKIRegistry {
    function isKYCValid(address _user) external view returns (bool);
    function canUserTransfer(address _user, uint256 _amount) external view returns (bool);
    function recordTransfer(address _user, uint256 _amount) external;
    function getUserPublicKey(address _user) external view returns (bytes memory);
}

/**
 * @dev Interface for BalanceVerifier contract
 */
interface IBalanceVerifier {
    struct BalanceProof {
        uint256 amount;
        bytes32 commitmentHash;
        bytes proofBytes;
        address userAddress;
    }
    
    function verifyProof(BalanceProof memory proof) external returns (bool);
    function isProofVerified(bytes32 proofHash) external view returns (bool);
}

/**
 * @dev Interface cho PQCSignatureRegistry contract
 */
interface IPQCSignatureRegistry {
    function storePQCSignature(
        uint256 txId,
        bytes calldata pqcSignature,
        string calldata algorithm
    ) external;
}

/**
 * @title InterbankTransfer
 * @dev Smart contract quản lý giao dịch liên ngân hàng với PKI integration.
 *
 * Thiết kế tối giản để không vượt giới hạn kích thước contract (EIP‑170):
 * - KHÔNG lưu toàn bộ lịch sử giao dịch on-chain (chỉ emit events `Transfer`).
 * - ZKP được verify off-chain (Winterfell), on-chain chỉ kiểm tra integrity inputs + gọi verifier tối giản.
 * - PQC signatures được lưu trong contract riêng `PQCSignatureRegistry` (Interbank chỉ gọi registry).
 */
contract InterbankTransfer {
    // PKI Registry reference
    IPKIRegistry public pkiRegistry;
    bool public pkiEnabled;
    
    // Balance Verifier reference (ZKP verifier)
    IBalanceVerifier public balanceVerifier;
    bool public zkpEnabled;
    
    // PQC Signature Registry reference (lưu chữ ký PQC on-chain)
    IPQCSignatureRegistry public pqcRegistry;
    
    // Mapping từ address đến số dư (VND, nhưng lưu dưới dạng wei)
    mapping(address => uint256) public balances;
    
    // Mapping từ address đến bank code
    mapping(address => string) public bankCodes;
    
    // Đếm số lượng giao dịch đã thực hiện (dùng làm transactionId trong event)
    uint256 public transactionCounter;
    
    // Events
    event Deposit(address indexed user, uint256 amount, string bankCode);
    event Transfer(
        uint256 indexed transactionId,
        address indexed from,
        address indexed to,
        uint256 amount,
        string fromBank,
        string toBank,
        string description,
        uint256 timestamp
    );
    event BalanceUpdated(address indexed user, uint256 newBalance);
    
    // Chỉ owner (hoặc authorized banks) mới có thể thực hiện một số hàm
    address public owner;
    mapping(address => bool) public authorizedBanks;
    
    // Struct để nhóm batch transfer parameters (tránh stack too deep)
    struct BatchTransferParams {
        address[] recipients;
        uint256[] amounts;
        string[] toBankCodes;
        string[] descriptions;
    }
    
    // Struct để nhóm batch ZKP parameters (tránh stack too deep)
    struct BatchZKPParams {
        uint256[] proofAmounts;
        bytes32[] commitmentHashes;
        bytes[] proofBytesArray;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyAuthorized() {
        require(
            authorizedBanks[msg.sender] || msg.sender == owner,
            "Not authorized"
        );
        _;
    }
    
    constructor() {
        owner = msg.sender;
        transactionCounter = 0;
        pkiEnabled = false; // Will be enabled after PKI deployment
        zkpEnabled = false; // Will be enabled after BalanceVerifier deployment
    }
    
    /**
     * @dev Set PKI Registry address (only owner)
     */
    function setPKIRegistry(address _pkiRegistry) external onlyOwner {
        require(_pkiRegistry != address(0), "Invalid PKI address");
        pkiRegistry = IPKIRegistry(_pkiRegistry);
        pkiEnabled = true;
    }
    
    /**
     * @dev Toggle PKI enforcement
     */
    function togglePKI(bool _enabled) external onlyOwner {
        pkiEnabled = _enabled;
    }
    
    /**
     * @dev Set Balance Verifier address (only owner)
     */
    function setBalanceVerifier(address _balanceVerifier) external onlyOwner {
        require(_balanceVerifier != address(0), "Invalid verifier address");
        balanceVerifier = IBalanceVerifier(_balanceVerifier);
        zkpEnabled = true;
    }
    
    /**
     * @dev Set PQC Signature Registry address (only owner)
     */
    function setPQCRegistry(address _pqcRegistry) external onlyOwner {
        require(_pqcRegistry != address(0), "Invalid PQC registry address");
        pqcRegistry = IPQCSignatureRegistry(_pqcRegistry);
    }
    
    /**
     * @dev Toggle ZKP enforcement
     */
    function toggleZKP(bool _enabled) external onlyOwner {
        require(address(balanceVerifier) != address(0), "BalanceVerifier not set");
        zkpEnabled = _enabled;
    }
    
    /**
     * @dev Thêm bank được ủy quyền
     */
    function addAuthorizedBank(address bankAddress, string memory bankCode)
        public
        onlyOwner
    {
        authorizedBanks[bankAddress] = true;
        bankCodes[bankAddress] = bankCode;
    }
    
    /**
     * @dev Nạp tiền vào tài khoản (chỉ authorized banks)
     */
    function deposit(address user, string memory bankCode)
        public
        payable
        onlyAuthorized
    {
        require(user != address(0), "Invalid user address");
        require(msg.value > 0, "Amount must be greater than 0");
        
        balances[user] += msg.value;
        bankCodes[user] = bankCode;
        
        emit Deposit(user, msg.value, bankCode);
        emit BalanceUpdated(user, balances[user]);
    }
    
    /**
     * @dev Lấy số dư của một address
     */
    function getBalance(address user) public view returns (uint256) {
        return balances[user];
    }
    
    /**
     * @dev Chuyển tiền liên ngân hàng
     * @param to Địa chỉ người nhận
     * @param amount Số tiền (trong wei)
     * @param toBankCode Mã ngân hàng nhận
     * @param description Mô tả giao dịch
     * @return transactionId ID của giao dịch
     */
    function transfer(
        address to,
        uint256 amount,
        string memory toBankCode,
        string memory description
    ) public returns (uint256) {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        require(
            balances[msg.sender] >= amount,
            "Insufficient balance"
        );
        require(msg.sender != to, "Cannot transfer to yourself");
        
        // PKI Verification (if enabled)
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            require(pkiRegistry.isKYCValid(msg.sender), "KYC not valid");
            require(pkiRegistry.canUserTransfer(msg.sender, amount), "Transfer not authorized or exceeds daily limit");
        }
        
        // Cập nhật số dư
        balances[msg.sender] -= amount;
        balances[to] += amount;
        
        // Sinh transactionId mới & phát events (lưu history qua event, không lưu struct)
        transactionCounter++;
        uint256 txId = transactionCounter;

        emit Transfer(
            txId,
            msg.sender,
            to,
            amount,
            bankCodes[msg.sender],
            toBankCode,
            description,
            block.timestamp
        );
        emit BalanceUpdated(msg.sender, balances[msg.sender]);
        emit BalanceUpdated(to, balances[to]);
        
        // Record transfer in PKI (if enabled)
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            pkiRegistry.recordTransfer(msg.sender, amount);
        }
        
        return txId;
    }
    
    /**
     * @dev Chuyển tiền với PQC signature (lưu signature on-chain)
     * @param to Địa chỉ người nhận
     * @param amount Số tiền (trong wei)
     * @param toBankCode Mã ngân hàng nhận
     * @param description Mô tả giao dịch
     * @param pqcSignature PQC signature (Base64 encoded bytes)
     * @param algorithm PQC algorithm name (e.g., "Dilithium3")
     * @return transactionId ID của giao dịch
     */
    function transferWithPQC(
        address to,
        uint256 amount,
        string memory toBankCode,
        string memory description,
        bytes memory pqcSignature,
        string memory algorithm
    ) public returns (uint256) {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        require(
            balances[msg.sender] >= amount,
            "Insufficient balance"
        );
        require(msg.sender != to, "Cannot transfer to yourself");
        require(pqcSignature.length > 0, "PQC signature cannot be empty");
        require(bytes(algorithm).length > 0, "Algorithm cannot be empty");
        
        // PKI Verification (if enabled)
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            require(pkiRegistry.isKYCValid(msg.sender), "KYC not valid");
            require(pkiRegistry.canUserTransfer(msg.sender, amount), "Transfer not authorized or exceeds daily limit");
        }
        
        // Lưu PQC signature on-chain qua PQCSignatureRegistry (nếu đã cấu hình)
        // (Nếu chưa cấu hình pqcRegistry thì vẫn cho phép chuyển tiền nhưng không lưu chữ ký)
        
        // Cập nhật số dư
        balances[msg.sender] -= amount;
        balances[to] += amount;
        
        // Sinh transactionId mới & phát events
        transactionCounter++;
        uint256 txId = transactionCounter;

        emit Transfer(
            txId,
            msg.sender,
            to,
            amount,
            bankCodes[msg.sender],
            toBankCode,
            description,
            block.timestamp
        );
        emit BalanceUpdated(msg.sender, balances[msg.sender]);
        emit BalanceUpdated(to, balances[to]);
        
        // Lưu PQC signature on-chain sau khi transfer thành công
        if (address(pqcRegistry) != address(0)) {
            pqcRegistry.storePQCSignature(txId, pqcSignature, algorithm);
        }
        
        // Record transfer in PKI (if enabled)
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            pkiRegistry.recordTransfer(msg.sender, amount);
        }
        
        return txId;
    }
    
    /**
     * @dev Chuyển tiền với ZKP proof (balance > amount)
     * @param to Địa chỉ người nhận
     * @param amount Số tiền (trong wei)
     * @param toBankCode Mã ngân hàng nhận
     * @param description Mô tả giao dịch
     * @param proofAmount Số tiền trong proof
     * @param commitmentHash Hash của balance commitment
     * @param proofBytes Proof bytes từ ZKP prover
     * @return transactionId ID của giao dịch
     */
    function transferWithZKP(
        address to,
        uint256 amount,
        string memory toBankCode,
        string memory description,
        uint256 proofAmount,
        bytes32 commitmentHash,
        bytes memory proofBytes
    ) public returns (uint256) {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        require(msg.sender != to, "Cannot transfer to yourself");
        require(zkpEnabled && address(balanceVerifier) != address(0), "ZKP not enabled");
        require(proofAmount == amount, "Proof amount mismatch");
        
        // Tạo BalanceProof struct
        IBalanceVerifier.BalanceProof memory proof = IBalanceVerifier.BalanceProof({
            amount: proofAmount,
            commitmentHash: commitmentHash,
            proofBytes: proofBytes,
            userAddress: msg.sender
        });
        
        // Verify ZKP proof
        bool verified = balanceVerifier.verifyProof(proof);
        require(verified, "ZKP proof verification failed");
        
        // Verify balance từ contract (double check)
        // Note: Trong production, balance sẽ được verify từ commitment
        // nhưng để đảm bảo tính nhất quán, chúng ta vẫn check balance thực tế
        require(
            balances[msg.sender] >= amount,
            "Insufficient balance"
        );
        
        // PKI Verification (if enabled)
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            require(pkiRegistry.isKYCValid(msg.sender), "KYC not valid");
            require(pkiRegistry.canUserTransfer(msg.sender, amount), "Transfer not authorized or exceeds daily limit");
        }
        
        // Cập nhật số dư
        balances[msg.sender] -= amount;
        balances[to] += amount;
        
        // Sinh transactionId mới & phát events
        transactionCounter++;
        uint256 txId = transactionCounter;

        emit Transfer(
            txId,
            msg.sender,
            to,
            amount,
            bankCodes[msg.sender],
            toBankCode,
            description,
            block.timestamp
        );
        emit BalanceUpdated(msg.sender, balances[msg.sender]);
        emit BalanceUpdated(to, balances[to]);
        
        // Record transfer in PKI (if enabled)
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            pkiRegistry.recordTransfer(msg.sender, amount);
        }
        
        return txId;
    }
    
    /**
     * @dev Get user's PQC public key from PKI
     */
    function getUserPublicKey(address user) external view returns (bytes memory) {
        require(pkiEnabled && address(pkiRegistry) != address(0), "PKI not enabled");
        return pkiRegistry.getUserPublicKey(user);
    }
    
    /**
     * @dev Check if user can transfer amount
     */
    function checkTransferAuthorization(address user, uint256 amount) external view returns (bool) {
        if (!pkiEnabled || address(pkiRegistry) == address(0)) {
            return true; // PKI not enforced
        }
        return pkiRegistry.isKYCValid(user) && pkiRegistry.canUserTransfer(user, amount);
    }
    
    /**
     * @dev Rút tiền từ contract (withdraw)
     * @param amount Số tiền cần rút (trong wei)
     * @param description Mô tả giao dịch rút tiền
     * @return transactionId ID của giao dịch
     */
    function withdraw(uint256 amount, string memory description) public returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");
        
        // PKI Verification (if enabled) - rút tiền cũng cần KYC
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            require(pkiRegistry.isKYCValid(msg.sender), "KYC not valid");
            // Withdraw không cần check daily limit vì đây là rút tiền, không phải transfer
        }
        
        // Trừ số dư từ contract
        balances[msg.sender] -= amount;
        emit BalanceUpdated(msg.sender, balances[msg.sender]);

        // Sinh transactionId mới & phát events (chỉ để tracking, không gửi native ETH)
        transactionCounter++;
        uint256 txId = transactionCounter;

        emit Transfer(
            txId,
            msg.sender,
            address(0),
            amount,
            bankCodes[msg.sender],
            "WITHDRAWAL",
            description,
            block.timestamp
        );
        return txId;
    }
    
    /**
     * @dev Batch transfer - OPTIMIZED for high TPS
     * Gửi nhiều transfers trong một transaction để giảm gas cost và tăng TPS
     * @param recipients Mảng địa chỉ người nhận
     * @param amounts Mảng số tiền tương ứng (trong wei)
     * @param toBankCodes Mảng mã ngân hàng nhận
     * @param descriptions Mảng mô tả giao dịch
     * @return transactionIds Mảng transaction IDs
     */
    function batchTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata toBankCodes,
        string[] calldata descriptions
    ) public returns (uint256[] memory) {
        require(recipients.length > 0, "Empty recipients array");
        require(
            recipients.length == amounts.length &&
            recipients.length == toBankCodes.length &&
            recipients.length == descriptions.length,
            "Array length mismatch"
        );
        require(recipients.length <= 50, "Batch size too large"); // Limit batch size
        
        uint256[] memory transactionIds = new uint256[](recipients.length);
        uint256 totalAmount = 0;
        
        // Calculate total amount first (gas optimization: single check)
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            require(amounts[i] > 0, "Amount must be greater than 0");
            require(msg.sender != recipients[i], "Cannot transfer to yourself");
            totalAmount += amounts[i];
        }
        
        // Single balance check for all transfers (gas optimization)
        require(balances[msg.sender] >= totalAmount, "Insufficient balance");
        
        // PKI Verification (if enabled) - check once for batch
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            require(pkiRegistry.isKYCValid(msg.sender), "KYC not valid");
            require(pkiRegistry.canUserTransfer(msg.sender, totalAmount), "Transfer not authorized or exceeds daily limit");
        }
        
        // Process all transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            // Update balances
            balances[msg.sender] -= amounts[i];
            balances[recipients[i]] += amounts[i];
            
            // Generate transaction ID
            transactionCounter++;
            uint256 txId = transactionCounter;
            transactionIds[i] = txId;
            
            // Emit events (packed for gas optimization)
            emit Transfer(
                txId,
                msg.sender,
                recipients[i],
                amounts[i],
                bankCodes[msg.sender],
                toBankCodes[i],
                descriptions[i],
                block.timestamp
            );
        }
        
        // Emit balance updates (optimized: only emit once per address)
        emit BalanceUpdated(msg.sender, balances[msg.sender]);
        for (uint256 i = 0; i < recipients.length; i++) {
            emit BalanceUpdated(recipients[i], balances[recipients[i]]);
        }
        
        // Record transfer in PKI (if enabled) - single call for batch
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            pkiRegistry.recordTransfer(msg.sender, totalAmount);
        }
        
        return transactionIds;
    }
    
    /**
     * @dev Internal function to verify a single ZKP proof (to avoid stack too deep)
     */
    function _verifyZKPProof(
        uint256 proofAmount,
        bytes32 commitmentHash,
        bytes memory proofBytes,
        address userAddress
    ) internal returns (bool) {
        IBalanceVerifier.BalanceProof memory proof = IBalanceVerifier.BalanceProof({
            amount: proofAmount,
            commitmentHash: commitmentHash,
            proofBytes: proofBytes,
            userAddress: userAddress
        });
        return balanceVerifier.verifyProof(proof);
    }
    
    /**
     * @dev Internal function to verify a single proof item (to avoid stack too deep)
     */
    function _verifyProofItem(
        address recipient,
        uint256 amount,
        uint256 proofAmount,
        bytes32 commitmentHash,
        bytes calldata proofBytes,
        address sender
    ) internal returns (bool) {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        require(sender != recipient, "Cannot transfer to yourself");
        require(proofAmount == amount, "Proof amount mismatch");
        
        return _verifyZKPProof(proofAmount, commitmentHash, proofBytes, sender);
    }
    
    
    /**
     * @dev Internal function to process batch transfers (to avoid stack too deep)
     */
    function _processBatchTransfers(
        address[] memory recipients,
        uint256[] memory amounts,
        string[] memory toBankCodes,
        string[] memory descriptions,
        uint256[] memory transactionIds,
        address sender
    ) internal {
        uint256 currentCounter = transactionCounter;
        uint256 len = recipients.length;
        string memory senderBankCode = bankCodes[sender];
        for (uint256 i = 0; i < len; i++) {
            balances[sender] -= amounts[i];
            balances[recipients[i]] += amounts[i];
            
            currentCounter++;
            transactionIds[i] = currentCounter;
            
            emit Transfer(
                currentCounter,
                sender,
                recipients[i],
                amounts[i],
                senderBankCode,
                toBankCodes[i],
                descriptions[i],
                block.timestamp
            );
        }
        transactionCounter = currentCounter;
        
        emit BalanceUpdated(sender, balances[sender]);
        for (uint256 i = 0; i < len; i++) {
            emit BalanceUpdated(recipients[i], balances[recipients[i]]);
        }
    }
    
    /**
     * @dev Batch transfer with ZKP proofs - OPTIMIZED
     * @param recipients Mảng địa chỉ người nhận
     * @param amounts Mảng số tiền
     * @param toBankCodes Mảng mã ngân hàng
     * @param descriptions Mảng mô tả
     * @param proofAmounts Mảng proof amounts
     * @param commitmentHashes Mảng commitment hashes
     * @param proofBytesArray Mảng proof bytes
     * @return transactionIds Mảng transaction IDs
     */
    /**
     * @dev Internal function to validate batch inputs (to avoid stack too deep)
     */
    function _validateBatchInputs(
        BatchTransferParams memory params,
        BatchZKPParams memory zkpParams
    ) internal pure returns (uint256) {
        uint256 batchSize = params.recipients.length;
        require(batchSize > 0, "Empty recipients array");
        require(
            batchSize == params.amounts.length &&
            batchSize == params.toBankCodes.length &&
            batchSize == params.descriptions.length &&
            batchSize == zkpParams.proofAmounts.length &&
            batchSize == zkpParams.commitmentHashes.length &&
            batchSize == zkpParams.proofBytesArray.length,
            "Array length mismatch"
        );
        require(batchSize <= 50, "Batch size too large");
        return batchSize;
    }
    
    /**
     * @dev Internal function to execute batch transfer after validation (to avoid stack too deep)
     */
    function _executeBatchTransferWithZKP(
        BatchTransferParams memory params,
        uint256[] memory transactionIds,
        address sender,
        uint256 totalAmount
    ) internal {
        // Single balance check
        require(balances[sender] >= totalAmount, "Insufficient balance");
        
        // PKI Verification (if enabled)
        bool pkiCheck = pkiEnabled && address(pkiRegistry) != address(0);
        if (pkiCheck) {
            require(pkiRegistry.isKYCValid(sender), "KYC not valid");
            require(pkiRegistry.canUserTransfer(sender, totalAmount), "Transfer not authorized or exceeds daily limit");
        }
        
        // Process all transfers
        _processBatchTransfers(
            params.recipients,
            params.amounts,
            params.toBankCodes,
            params.descriptions,
            transactionIds,
            sender
        );
        
        if (pkiCheck) {
            pkiRegistry.recordTransfer(sender, totalAmount);
        }
    }
    
    /**
     * @dev Internal function to verify batch proofs and calculate total amount
     */
    function _verifyBatchProofs(
        BatchTransferParams memory params,
        BatchZKPParams memory zkpParams,
        address sender
    ) internal returns (uint256) {
        uint256 batchSize = params.recipients.length;
        uint256 totalAmount = 0;
        
        for (uint256 i = 0; i < batchSize; i++) {
            require(params.amounts[i] == zkpParams.proofAmounts[i], "Amount mismatch");
            
            IBalanceVerifier.BalanceProof memory proof = IBalanceVerifier.BalanceProof({
                amount: zkpParams.proofAmounts[i],
                commitmentHash: zkpParams.commitmentHashes[i],
                proofBytes: zkpParams.proofBytesArray[i],
                userAddress: sender
            });
            
            require(balanceVerifier.verifyProof(proof), "Invalid ZKP proof");
            totalAmount += params.amounts[i];
        }
        
        return totalAmount;
    }
    
    /**
     * @dev Internal function to validate batch size
     */
    function _validateBatchSize(uint256 size) internal pure {
        require(size > 0, "Empty recipients array");
        require(size <= 50, "Batch size too large");
    }
    
    /**
     * @dev Internal function to check array length matches
     */
    function _checkArrayLength(uint256 expected, uint256 actual) internal pure {
        require(expected == actual, "Array length mismatch");
    }
    
    /**
     * @dev Internal function to verify batch proofs and calculate total amount (without structs)
     */
    function _verifyBatchProofsDirect(
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint256[] calldata proofAmounts,
        bytes32[] calldata commitmentHashes,
        bytes[] calldata proofBytesArray,
        address sender
    ) internal returns (uint256) {
        uint256 batchSize = recipients.length;
        uint256 totalAmount = 0;
        
        for (uint256 i = 0; i < batchSize; i++) {
            require(amounts[i] == proofAmounts[i], "Amount mismatch");
            
            IBalanceVerifier.BalanceProof memory proof = IBalanceVerifier.BalanceProof({
                amount: proofAmounts[i],
                commitmentHash: commitmentHashes[i],
                proofBytes: proofBytesArray[i],
                userAddress: sender
            });
            
            require(balanceVerifier.verifyProof(proof), "Invalid ZKP proof");
            totalAmount += amounts[i];
        }
        
        return totalAmount;
    }
    
    /**
     * @dev Internal function to check balance and PKI (to avoid stack too deep)
     */
    function _checkBalanceAndPKI(address sender, uint256 totalAmount) internal view {
        require(balances[sender] >= totalAmount, "Insufficient balance");
        
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            require(pkiRegistry.isKYCValid(sender), "KYC not valid");
            require(pkiRegistry.canUserTransfer(sender, totalAmount), "Transfer not authorized or exceeds daily limit");
        }
    }
    
    /**
     * @dev Verify batch proofs and calculate total amount (to avoid stack too deep)
     * Uses separate functions to reduce stack depth
     */
    function _verifyBatchProofsAndCalculateTotal(
        uint256[] calldata amounts,
        uint256[] calldata proofAmounts,
        bytes32[] calldata commitmentHashes,
        bytes[] calldata proofBytesArray,
        address sender,
        uint256 batchSize
    ) internal returns (uint256) {
        // Step 1: Copy and validate amounts
        uint256[] memory amountsMem = _copyUint256Array(amounts, batchSize);
        uint256[] memory proofAmountsMem = _copyUint256Array(proofAmounts, batchSize);
        uint256 totalAmount = _validateAmountsAndCalculateTotal(amountsMem, proofAmountsMem, batchSize);
        
        // Step 2: Copy and verify proofs
        bytes32[] memory commitmentHashesMem = _copyBytes32Array(commitmentHashes, batchSize);
        bytes[] memory proofBytesArrayMem = _copyBytesArray(proofBytesArray, batchSize);
        _verifyAllProofs(proofAmountsMem, commitmentHashesMem, proofBytesArrayMem, sender, batchSize);
        
        return totalAmount;
    }
    
    /**
     * @dev Validate amounts and calculate total (to avoid stack too deep)
     */
    function _validateAmountsAndCalculateTotal(
        uint256[] memory amountsMem,
        uint256[] memory proofAmountsMem,
        uint256 batchSize
    ) internal pure returns (uint256) {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < batchSize; i++) {
            require(amountsMem[i] == proofAmountsMem[i], "Amount mismatch");
            totalAmount += amountsMem[i];
        }
        return totalAmount;
    }
    
    /**
     * @dev Verify all ZKP proofs (to avoid stack too deep)
     */
    function _verifyAllProofs(
        uint256[] memory proofAmountsMem,
        bytes32[] memory commitmentHashesMem,
        bytes[] memory proofBytesArrayMem,
        address sender,
        uint256 batchSize
    ) internal {
        for (uint256 i = 0; i < batchSize; i++) {
            require(_verifyZKPProof(proofAmountsMem[i], commitmentHashesMem[i], proofBytesArrayMem[i], sender), "Invalid ZKP proof");
        }
    }
    
    /**
     * @dev Helper functions to copy arrays to memory (to avoid stack too deep)
     */
    function _copyAddressArray(address[] calldata src, uint256 size) internal pure returns (address[] memory) {
        address[] memory dst = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            dst[i] = src[i];
        }
        return dst;
    }
    
    function _copyUint256Array(uint256[] calldata src, uint256 size) internal pure returns (uint256[] memory) {
        uint256[] memory dst = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            dst[i] = src[i];
        }
        return dst;
    }
    
    function _copyStringArray(string[] calldata src, uint256 size) internal pure returns (string[] memory) {
        string[] memory dst = new string[](size);
        for (uint256 i = 0; i < size; i++) {
            dst[i] = src[i];
        }
        return dst;
    }
    
    function _copyBytes32Array(bytes32[] calldata src, uint256 size) internal pure returns (bytes32[] memory) {
        bytes32[] memory dst = new bytes32[](size);
        for (uint256 i = 0; i < size; i++) {
            dst[i] = src[i];
        }
        return dst;
    }
    
    function _copyBytesArray(bytes[] calldata src, uint256 size) internal pure returns (bytes[] memory) {
        bytes[] memory dst = new bytes[](size);
        for (uint256 i = 0; i < size; i++) {
            dst[i] = src[i];
        }
        return dst;
    }
    
    /**
     * @dev Helper struct to group arrays (to avoid stack too deep)
     */
    struct BatchZKPArrays {
        address[] recipients;
        uint256[] amounts;
        string[] toBankCodes;
        string[] descriptions;
        uint256[] proofAmounts;
        bytes32[] commitmentHashes;
        bytes[] proofBytesArray;
    }
    
    /**
     * @dev Batch verify ZKP proofs (separate function to avoid stack too deep)
     * @param amounts Array of amounts
     * @param proofAmounts Array of proof amounts
     * @param commitmentHashes Array of commitment hashes
     * @param proofBytesArray Array of proof bytes
     * @return totalAmount Total amount after verification
     */
    function batchVerifyZKP(
        uint256[] calldata amounts,
        uint256[] calldata proofAmounts,
        bytes32[] calldata commitmentHashes,
        bytes[] calldata proofBytesArray
    ) public returns (uint256) {
        require(zkpEnabled && address(balanceVerifier) != address(0), "ZKP not enabled");
        
        uint256 batchSize = amounts.length;
        _validateBatchSize(batchSize);
        _checkArrayLength(batchSize, proofAmounts.length);
        _checkArrayLength(batchSize, commitmentHashes.length);
        _checkArrayLength(batchSize, proofBytesArray.length);
        
        return _verifyBatchZKPProofs(amounts, proofAmounts, commitmentHashes, proofBytesArray, batchSize);
    }
    
    /**
     * @dev Batch transfer after ZKP verification (separate function to avoid stack too deep)
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts
     * @param toBankCodes Array of bank codes
     * @param descriptions Array of descriptions
     * @param totalAmount Total amount (from batchVerifyZKP)
     * @return transactionIds Array of transaction IDs
     */
    function batchTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata toBankCodes,
        string[] calldata descriptions,
        uint256 totalAmount
    ) public returns (uint256[] memory) {
        uint256 batchSize = recipients.length;
        _validateBatchSize(batchSize);
        _checkArrayLength(batchSize, amounts.length);
        _checkArrayLength(batchSize, toBankCodes.length);
        _checkArrayLength(batchSize, descriptions.length);
        
        address sender = msg.sender;
        _checkBalanceAndPKI(sender, totalAmount);
        
        uint256[] memory transactionIds = new uint256[](batchSize);
        address[] memory r = _copyAddressArray(recipients, batchSize);
        uint256[] memory a = _copyUint256Array(amounts, batchSize);
        string[] memory tbc = _copyStringArray(toBankCodes, batchSize);
        string[] memory d = _copyStringArray(descriptions, batchSize);
        _processBatchTransfers(r, a, tbc, d, transactionIds, sender);
        
        if (pkiEnabled && address(pkiRegistry) != address(0)) {
            pkiRegistry.recordTransfer(sender, totalAmount);
        }
        
        return transactionIds;
    }
    
    
    /**
     * @dev Verify batch ZKP proofs (separate function to reduce stack depth)
     */
    function _verifyBatchZKPProofs(
        uint256[] calldata amounts,
        uint256[] calldata proofAmounts,
        bytes32[] calldata commitmentHashes,
        bytes[] calldata proofBytesArray,
        uint256 batchSize
    ) internal returns (uint256) {
        address sender = msg.sender;
        uint256[] memory a = _copyUint256Array(amounts, batchSize);
        uint256[] memory pa = _copyUint256Array(proofAmounts, batchSize);
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < batchSize; i++) {
            require(a[i] == pa[i], "Amount mismatch");
            totalAmount += a[i];
        }
        bytes32[] memory ch = _copyBytes32Array(commitmentHashes, batchSize);
        bytes[] memory pba = _copyBytesArray(proofBytesArray, batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            require(_verifyZKPProof(pa[i], ch[i], pba[i], sender), "Invalid ZKP proof");
        }
        return totalAmount;
    }
    
}

