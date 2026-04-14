// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title PKIRegistry
 * @dev Public Key Infrastructure Registry for Interbank Blockchain
 * @notice Manages PQC public keys, KYC status, and user authorization
 * 
 * Features:
 * - Store Dilithium3 public keys
 * - KYC compliance tracking
 * - Account ownership verification
 * - Key rotation support
 * - Authorization management
 */
contract PKIRegistry {
    
    // ========== STRUCTS ==========
    
    /**
     * @dev User identity with PQC public key
     */
    struct UserIdentity {
        address userAddress;        // Ethereum address
        bytes pqcPublicKey;         // Dilithium3 public key (~1952 bytes)
        bytes32 keyHash;            // Hash of public key for quick lookup
        bool isActive;              // Active status
        uint256 registeredAt;       // Registration timestamp
        uint256 lastUpdated;        // Last update timestamp
    }
    
    /**
     * @dev KYC information (privacy-preserving)
     */
    struct KYCInfo {
        bool isVerified;            // KYC verified status
        uint256 verifiedAt;         // Verification timestamp
        uint256 expiresAt;          // Expiration timestamp
        bytes32 kycHash;            // Hash of KYC data (not the actual data)
        address verifier;           // KYC verifier (bank)
    }
    
    /**
     * @dev Authorization permissions
     */
    struct Authorization {
        bool canTransfer;           // Can initiate transfers
        bool canReceive;            // Can receive transfers
        uint256 dailyLimit;         // Daily transfer limit (wei)
        uint256 usedToday;          // Amount used today
        uint256 lastResetDate;      // Last daily limit reset
    }
    
    // ========== STATE VARIABLES ==========
    
    // Mapping: address => UserIdentity
    mapping(address => UserIdentity) public users;
    
    // Mapping: address => KYCInfo
    mapping(address => KYCInfo) public kycRecords;
    
    // Mapping: address => Authorization
    mapping(address => Authorization) public authorizations;
    
    // Mapping: keyHash => address (for reverse lookup)
    mapping(bytes32 => address) public keyHashToAddress;
    
    // Authorized banks (can verify KYC)
    mapping(address => bool) public authorizedBanks;
    
    // Contract owner
    address public owner;
    
    // Total registered users
    uint256 public totalUsers;
    
    // ========== EVENTS ==========
    
    event UserRegistered(
        address indexed userAddress,
        bytes32 keyHash,
        uint256 timestamp
    );
    
    event PublicKeyUpdated(
        address indexed userAddress,
        bytes32 oldKeyHash,
        bytes32 newKeyHash,
        uint256 timestamp
    );
    
    event KYCVerified(
        address indexed userAddress,
        address indexed verifier,
        uint256 expiresAt
    );
    
    event KYCRevoked(
        address indexed userAddress,
        address indexed revoker
    );
    
    event AuthorizationUpdated(
        address indexed userAddress,
        bool canTransfer,
        bool canReceive,
        uint256 dailyLimit
    );
    
    event BankAuthorized(
        address indexed bankAddress,
        bool authorized
    );
    
    // ========== MODIFIERS ==========
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier onlyAuthorizedBank() {
        require(authorizedBanks[msg.sender], "Only authorized bank");
        _;
    }
    
    modifier userExists(address _user) {
        require(users[_user].isActive, "User not registered");
        _;
    }
    
    modifier userNotExists(address _user) {
        require(!users[_user].isActive, "User already registered");
        _;
    }
    
    // ========== CONSTRUCTOR ==========
    
    constructor() {
        owner = msg.sender;
    }
    
    // ========== USER REGISTRATION ==========
    
    /**
     * @dev Register new user with PQC public key
     * @param _pqcPublicKey Dilithium3 public key (bytes)
     */
    function registerUser(bytes memory _pqcPublicKey) external userNotExists(msg.sender) {
        require(_pqcPublicKey.length > 0, "Empty public key");
        require(_pqcPublicKey.length <= 3000, "Public key too large"); // Dilithium3 ~1952 bytes
        
        bytes32 keyHash = keccak256(_pqcPublicKey);
        require(keyHashToAddress[keyHash] == address(0), "Public key already registered");
        
        // Store user identity
        users[msg.sender] = UserIdentity({
            userAddress: msg.sender,
            pqcPublicKey: _pqcPublicKey,
            keyHash: keyHash,
            isActive: true,
            registeredAt: block.timestamp,
            lastUpdated: block.timestamp
        });
        
        // Map key hash to address
        keyHashToAddress[keyHash] = msg.sender;
        
        // Initialize authorization (default: restricted)
        authorizations[msg.sender] = Authorization({
            canTransfer: false,
            canReceive: true,  // Can receive by default
            dailyLimit: 0,
            usedToday: 0,
            lastResetDate: block.timestamp / 1 days
        });
        
        totalUsers++;
        
        emit UserRegistered(msg.sender, keyHash, block.timestamp);
    }
    
    /**
     * @dev Update user's PQC public key (key rotation)
     * @param _newPqcPublicKey New Dilithium3 public key
     */
    function updatePublicKey(bytes memory _newPqcPublicKey) external userExists(msg.sender) {
        require(_newPqcPublicKey.length > 0, "Empty public key");
        require(_newPqcPublicKey.length <= 3000, "Public key too large");
        
        bytes32 newKeyHash = keccak256(_newPqcPublicKey);
        require(keyHashToAddress[newKeyHash] == address(0), "Public key already in use");
        
        UserIdentity storage user = users[msg.sender];
        bytes32 oldKeyHash = user.keyHash;
        
        // Remove old key hash mapping
        delete keyHashToAddress[oldKeyHash];
        
        // Update to new key
        user.pqcPublicKey = _newPqcPublicKey;
        user.keyHash = newKeyHash;
        user.lastUpdated = block.timestamp;
        
        // Map new key hash
        keyHashToAddress[newKeyHash] = msg.sender;
        
        emit PublicKeyUpdated(msg.sender, oldKeyHash, newKeyHash, block.timestamp);
    }
    
    // ========== KYC MANAGEMENT ==========
    
    /**
     * @dev Verify user's KYC (only authorized banks)
     * @param _user User address
     * @param _kycHash Hash of KYC data (privacy-preserving)
     * @param _validityDays Validity period in days
     */
    function verifyKYC(
        address _user,
        bytes32 _kycHash,
        uint256 _validityDays
    ) external onlyAuthorizedBank userExists(_user) {
        require(_kycHash != bytes32(0), "Invalid KYC hash");
        require(_validityDays > 0 && _validityDays <= 365, "Invalid validity period");
        
        uint256 expiresAt = block.timestamp + (_validityDays * 1 days);
        
        kycRecords[_user] = KYCInfo({
            isVerified: true,
            verifiedAt: block.timestamp,
            expiresAt: expiresAt,
            kycHash: _kycHash,
            verifier: msg.sender
        });
        
        emit KYCVerified(_user, msg.sender, expiresAt);
    }
    
    /**
     * @dev Revoke user's KYC
     * @param _user User address
     */
    function revokeKYC(address _user) external onlyAuthorizedBank userExists(_user) {
        require(kycRecords[_user].isVerified, "KYC not verified");
        
        kycRecords[_user].isVerified = false;
        
        // Also revoke transfer permission
        authorizations[_user].canTransfer = false;
        
        emit KYCRevoked(_user, msg.sender);
    }
    
    /**
     * @dev Check if user's KYC is valid
     * @param _user User address
     * @return isValid True if KYC is verified and not expired
     */
    function isKYCValid(address _user) public view returns (bool) {
        KYCInfo memory kyc = kycRecords[_user];
        return kyc.isVerified && block.timestamp < kyc.expiresAt;
    }
    
    // ========== AUTHORIZATION MANAGEMENT ==========
    
    /**
     * @dev Set user authorization (only authorized banks)
     * @param _user User address
     * @param _canTransfer Can initiate transfers
     * @param _canReceive Can receive transfers
     * @param _dailyLimit Daily transfer limit (wei)
     */
    function setAuthorization(
        address _user,
        bool _canTransfer,
        bool _canReceive,
        uint256 _dailyLimit
    ) external onlyAuthorizedBank userExists(_user) {
        // Can only enable transfer if KYC is valid
        if (_canTransfer) {
            require(isKYCValid(_user), "KYC not valid");
        }
        
        Authorization storage auth = authorizations[_user];
        auth.canTransfer = _canTransfer;
        auth.canReceive = _canReceive;
        auth.dailyLimit = _dailyLimit;
        
        emit AuthorizationUpdated(_user, _canTransfer, _canReceive, _dailyLimit);
    }
    
    /**
     * @dev Check if user can transfer
     * @param _user User address
     * @param _amount Amount to transfer (wei)
     * @return canTransfer True if authorized and within limit
     */
    function canUserTransfer(address _user, uint256 _amount) public view returns (bool) {
        if (!users[_user].isActive) return false;
        if (!isKYCValid(_user)) return false;
        
        Authorization memory auth = authorizations[_user];
        if (!auth.canTransfer) return false;
        
        // Check daily limit
        uint256 today = block.timestamp / 1 days;
        if (today > auth.lastResetDate) {
            // New day, limit resets
            return _amount <= auth.dailyLimit;
        } else {
            // Same day, check remaining limit
            return (auth.usedToday + _amount) <= auth.dailyLimit;
        }
    }
    
    /**
     * @dev Record transfer usage (call from transfer contract)
     * @param _user User address
     * @param _amount Amount transferred
     */
    function recordTransfer(address _user, uint256 _amount) external {
        require(users[_user].isActive, "User not registered");
        
        Authorization storage auth = authorizations[_user];
        
        uint256 today = block.timestamp / 1 days;
        if (today > auth.lastResetDate) {
            // New day, reset counter
            auth.usedToday = _amount;
            auth.lastResetDate = today;
        } else {
            // Same day, add to counter
            auth.usedToday += _amount;
        }
    }
    
    // ========== BANK MANAGEMENT ==========
    
    /**
     * @dev Authorize a bank (only owner)
     * @param _bank Bank address
     * @param _authorized Authorization status
     */
    function authorizeBankAddress(address _bank, bool _authorized) external onlyOwner {
        require(_bank != address(0), "Invalid bank address");
        authorizedBanks[_bank] = _authorized;
        emit BankAuthorized(_bank, _authorized);
    }
    
    /**
     * @dev Batch authorize banks
     * @param _banks Array of bank addresses
     */
    function batchAuthorizeBanks(address[] memory _banks) external onlyOwner {
        for (uint i = 0; i < _banks.length; i++) {
            authorizedBanks[_banks[i]] = true;
            emit BankAuthorized(_banks[i], true);
        }
    }
    
    // ========== QUERY FUNCTIONS ==========
    
    /**
     * @dev Get user's PQC public key
     * @param _user User address
     * @return publicKey PQC public key bytes
     */
    function getUserPublicKey(address _user) external view userExists(_user) returns (bytes memory) {
        return users[_user].pqcPublicKey;
    }
    
    /**
     * @dev Get user by key hash
     * @param _keyHash Hash of public key
     * @return userAddress User's address
     */
    function getUserByKeyHash(bytes32 _keyHash) external view returns (address) {
        return keyHashToAddress[_keyHash];
    }
    
    /**
     * @dev Get full user info
     * @param _user User address
     * @return identity User identity information
     * @return kyc KYC information
     * @return auth Authorization information
     */
    function getUserInfo(address _user) external view userExists(_user) returns (
        UserIdentity memory identity,
        KYCInfo memory kyc,
        Authorization memory auth
    ) {
        return (
            users[_user],
            kycRecords[_user],
            authorizations[_user]
        );
    }
    
    /**
     * @dev Verify PQC signature (placeholder - actual verification off-chain via KSM)
     * @param _user User address
     * @param _message Message that was signed
     * @param _signature PQC signature
     * @return isValid True if signature is valid
     */
    function verifyPQCSignature(
        address _user,
        bytes memory _message,
        bytes memory _signature
    ) external view userExists(_user) returns (bool) {
        // In production: This would call KSM service off-chain
        // or use a precompile for on-chain verification
        
        // For now: Just check signature is not empty
        // Real verification happens in KSM service
        require(_message.length > 0, "Empty message");
        require(_signature.length > 0, "Empty signature");
        
        // Placeholder logic
        return _signature.length >= 2420; // Dilithium3 signature size
    }
    
    /**
     * @dev Get user statistics
     * @return total Total registered users
     * @return verified Total KYC verified users
     * @return authorized Total users with transfer permission
     */
    function getUserStats() external view returns (
        uint256 total,
        uint256 verified,
        uint256 authorized
    ) {
        total = totalUsers;
        verified = 0;
        authorized = 0;
        
        // Note: This is gas-intensive for large user base
        // In production: track these counters separately
    }
    
    // ========== ADMIN FUNCTIONS ==========
    
    /**
     * @dev Deactivate user account (emergency only)
     * @param _user User address
     */
    function deactivateUser(address _user) external onlyOwner userExists(_user) {
        users[_user].isActive = false;
        authorizations[_user].canTransfer = false;
        authorizations[_user].canReceive = false;
    }
    
    /**
     * @dev Transfer ownership
     * @param _newOwner New owner address
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid new owner");
        owner = _newOwner;
    }
}

