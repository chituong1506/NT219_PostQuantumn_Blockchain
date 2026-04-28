// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract CoreLedger {
    address public admin;

    mapping(address => uint256) private balances;
    mapping(address => bool) public registeredBanks;
    mapping(bytes32 => bool) public usedTransactionIds;
    mapping(bytes32 => bool) public validProofHashes;

    event BankRegistered(address indexed bank, uint256 initialBalance);

    event ProofRegistered(bytes32 indexed proofHash);

    event TransferExecuted(
        bytes32 indexed txId,
        address indexed fromBank,
        address indexed toBank,
        uint256 amount,
        bytes32 proofHash
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyRegisteredBank() {
        require(registeredBanks[msg.sender], "Not registered bank");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function registerBank(address bank, uint256 initialBalance) external onlyAdmin {
        require(bank != address(0), "Invalid address");
        require(!registeredBanks[bank], "Already registered");

        registeredBanks[bank] = true;
        balances[bank] = initialBalance;

        emit BankRegistered(bank, initialBalance);
    }

    function registerValidProof(bytes32 proofHash) external onlyAdmin {
        require(proofHash != bytes32(0), "Invalid proof");

        validProofHashes[proofHash] = true;

        emit ProofRegistered(proofHash);
    }

    function transferMoney(
        bytes32 txId,
        address toBank,
        uint256 amount,
        bytes32 proofHash
    ) external onlyRegisteredBank {
        require(!usedTransactionIds[txId], "Tx already used");
        require(registeredBanks[toBank], "Invalid receiver");
        require(amount > 0, "Invalid amount");
        require(balances[msg.sender] >= amount, "Not enough balance");
        require(validProofHashes[proofHash], "Invalid proof");

        usedTransactionIds[txId] = true;

        balances[msg.sender] -= amount;
        balances[toBank] += amount;

        emit TransferExecuted(txId, msg.sender, toBank, amount, proofHash);
    }

    function getBalance(address bank) external view returns (uint256) {
        return balances[bank];
    }
}