// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title KYCRestrictedToken
 * @dev ERC721 token with KYC verification requirements for transfers and holdings
 * Includes UUPS upgradability, multi-sig capabilities, and reentrancy protection
 */
contract KYCRestrictedToken is 
    Initializable, 
    ERC721Upgradeable, 
    UUPSUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    /// @notice Mapping to track KYC verification status of addresses
    mapping(address => bool) private _kycAllowlist;
    
    /// @notice Multi-sig wallet that serves as the allowlist manager
    address public allowlistManager;
    
    /// @notice Required number of confirmations for multi-sig operations
    uint256 public requiredConfirmations;
    
    /// @notice Owners of the multi-sig wallet
    address[] public owners;
    
    /// @notice Mapping to check if an address is an owner
    mapping(address => bool) public isOwner;
    
    /// @notice Struct to store transaction information
    struct Transaction {
        address target;
        bool isAddition; // true for adding to allowlist, false for removal
        bool executed;
        uint256 confirmations;
    }
    
    /// @notice Array to store all transaction requests
    Transaction[] public transactions;
    
    /// @notice Mapping to track confirmations of transactions
    mapping(uint256 => mapping(address => bool)) public confirmed;

    /// @dev Custom errors for common failure conditions
    error NotKYCVerified(address user);
    error NotAuthorized();
    error TransactionAlreadyExecuted();
    error InsufficientConfirmations();
    error InvalidTransactionId();
    error AlreadyConfirmed();
    error NotConfirmed();
    error OwnerAlreadyExists();
    error InvalidOwnerAddress();
    error NotAllowlistManager();
    error InvalidConfirmationCount();

    /// @dev Events for important contract activities
    event AllowlistUpdated(address indexed user, bool status);
    event TransactionSubmitted(uint256 indexed txIndex, address indexed target, bool isAddition);
    event TransactionConfirmed(uint256 indexed txIndex, address indexed owner);
    event TransactionExecuted(uint256 indexed txIndex);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event AllowlistManagerUpdated(address indexed oldManager, address indexed newManager);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with token details and multi-sig setup
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _owners Array of initial multi-sig owners
     * @param _requiredConfirmations Number of required confirmations
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address[] memory _owners,
        uint256 _requiredConfirmations
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        require(_owners.length > 0, "Owners required");
        require(_requiredConfirmations > 0 && _requiredConfirmations <= _owners.length, "Invalid confirmation count");
        
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner already exists");
            
            isOwner[owner] = true;
            owners.push(owner);
            
            emit OwnerAdded(owner);
        }
        
        requiredConfirmations = _requiredConfirmations;
        
        // Set the multi-sig contract itself as the allowlist manager
        allowlistManager = address(this);
        emit AllowlistManagerUpdated(address(0), allowlistManager);
    }
    
    /**
     * @dev Override for authorizing upgrades (UUPS pattern)
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // Only the contract owner can upgrade the implementation
    }
    
    /**
     * @dev Modifier to restrict function to allowlist manager
     */
    modifier onlyAllowlistManager() {
        if (msg.sender != allowlistManager) revert NotAllowlistManager();
        _;
    }
    
    /**
     * @dev Modifier to restrict function to multi-sig owners
     */
    modifier onlyMultiSigOwner() {
        if (!isOwner[msg.sender]) revert NotAuthorized();
        _;
    }
    
    /**
     * @dev Submits a transaction to add or remove an address from the KYC allowlist
     * @param _target The address to add or remove
     * @param _isAddition Whether to add (true) or remove (false) the address
     * @return txIndex Index of the transaction
     */
    function submitTransaction(address _target, bool _isAddition) 
        public 
        onlyMultiSigOwner 
        returns (uint256 txIndex) 
    {
        txIndex = transactions.length;
        
        transactions.push(Transaction({
            target: _target,
            isAddition: _isAddition,
            executed: false,
            confirmations: 0
        }));
        
        emit TransactionSubmitted(txIndex, _target, _isAddition);
        
        // Auto-confirm from the submitter
        confirmTransaction(txIndex);
        
        return txIndex;
    }
    
    /**
     * @dev Confirms a pending transaction
     * @param _txIndex Index of the transaction to confirm
     */
    function confirmTransaction(uint256 _txIndex) 
        public 
        onlyMultiSigOwner 
    {
        if (_txIndex >= transactions.length) revert InvalidTransactionId();
        if (confirmed[_txIndex][msg.sender]) revert AlreadyConfirmed();
        if (transactions[_txIndex].executed) revert TransactionAlreadyExecuted();
        
        confirmed[_txIndex][msg.sender] = true;
        transactions[_txIndex].confirmations += 1;
        
        emit TransactionConfirmed(_txIndex, msg.sender);
        
        // Execute automatically if enough confirmations
        if (transactions[_txIndex].confirmations >= requiredConfirmations) {
            executeTransaction(_txIndex);
        }
    }
    
    /**
     * @dev Revokes a confirmation for a transaction
     * @param _txIndex Index of the transaction
     */
    function revokeConfirmation(uint256 _txIndex) 
        public 
        onlyMultiSigOwner 
    {
        if (_txIndex >= transactions.length) revert InvalidTransactionId();
        if (!confirmed[_txIndex][msg.sender]) revert NotConfirmed();
        if (transactions[_txIndex].executed) revert TransactionAlreadyExecuted();
        
        confirmed[_txIndex][msg.sender] = false;
        transactions[_txIndex].confirmations -= 1;
    }
    
    /**
     * @dev Executes a confirmed transaction
     * @param _txIndex Index of the transaction to execute
     */
    function executeTransaction(uint256 _txIndex) 
        public 
        nonReentrant 
    {
        if (_txIndex >= transactions.length) revert InvalidTransactionId();
        if (transactions[_txIndex].executed) revert TransactionAlreadyExecuted();
        if (transactions[_txIndex].confirmations < requiredConfirmations) revert InsufficientConfirmations();
        
        Transaction storage transaction = transactions[_txIndex];
        transaction.executed = true;
        
        // Update the KYC allowlist
        if (transaction.isAddition) {
            _addToAllowlist(transaction.target);
        } else {
            _removeFromAllowlist(transaction.target);
        }
        
        emit TransactionExecuted(_txIndex);
    }
    
    /**
     * @dev Internal function to add an address to the KYC allowlist
     * @param _user Address to add to the allowlist
     */
    function _addToAllowlist(address _user) private {
        _kycAllowlist[_user] = true;
        emit AllowlistUpdated(_user, true);
    }
    
    /**
     * @dev Internal function to remove an address from the KYC allowlist
     * @param _user Address to remove from the allowlist
     */
    function _removeFromAllowlist(address _user) private {
        _kycAllowlist[_user] = false;
        emit AllowlistUpdated(_user, false);
    }
    
    /**
     * @dev Checks if an address is on the KYC allowlist
     * @param _user Address to check
     * @return bool True if the address is on the allowlist
     */
    function isAllowlisted(address _user) public view returns (bool) {
        return _kycAllowlist[_user];
    }
    
    /**
     * @dev Gets the list of multi-sig owners
     * @return Address array of owners
     */
    function getOwners() public view returns (address[] memory) {
        return owners;
    }
    
    /**
     * @dev Gets the transaction count
     * @return uint256 Number of transactions
     */
    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }
    
    /**
     * @dev Gets details of a transaction
     * @param _txIndex Index of the transaction
     * @return target Address affected by the transaction
     * @return isAddition Whether it's an addition or removal
     * @return executed Whether the transaction was executed
     * @return confirmations Number of confirmations
     */
    function getTransaction(uint256 _txIndex)
        public
        view
        returns (
            address target,
            bool isAddition,
            bool executed,
            uint256 confirmations
        )
    {
        if (_txIndex >= transactions.length) revert InvalidTransactionId();
        
        Transaction storage transaction = transactions[_txIndex];
        
        return (
            transaction.target,
            transaction.isAddition,
            transaction.executed,
            transaction.confirmations
        );
    }
    
    /**
     * @dev Adds a new owner to the multi-sig
     * @param _owner Address of the new owner
     */
    function addOwner(address _owner) public onlyAllowlistManager {
        if (_owner == address(0)) revert InvalidOwnerAddress();
        if (isOwner[_owner]) revert OwnerAlreadyExists();
        
        isOwner[_owner] = true;
        owners.push(_owner);
        
        emit OwnerAdded(_owner);
    }
    
    /**
     * @dev Removes an owner from the multi-sig
     * @param _owner Address of the owner to remove
     */
    function removeOwner(address _owner) public onlyAllowlistManager {
        if (!isOwner[_owner]) revert InvalidOwnerAddress();
        
        isOwner[_owner] = false;
        
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        
        // Adjust required confirmations if necessary
        if (requiredConfirmations > owners.length) {
            requiredConfirmations = owners.length;
        }
        
        emit OwnerRemoved(_owner);
    }
    
    /**
     * @dev Changes the required number of confirmations
     * @param _requiredConfirmations New number of required confirmations
     */
    function changeRequiredConfirmations(uint256 _requiredConfirmations) public onlyAllowlistManager {
        if (_requiredConfirmations == 0 || _requiredConfirmations > owners.length) revert InvalidConfirmationCount();
        
        requiredConfirmations = _requiredConfirmations;
    }
    
    /**
     * @dev Hook that is called before any token transfer
     * This overrides the ERC721Upgradeable _beforeTokenTransfer function for KYC checks
     */
    function _beforeTokenTransfer(
        address from,
        address to
    ) internal virtual {
        // Skip KYC check for minting (from == 0) and burning (to == 0)
        if (from != address(0) && to != address(0)) {
            // Check if recipient is KYC verified
            if (!isAllowlisted(to)) {
                revert NotKYCVerified(to);
            }
        }
        
        // No need to call super._beforeTokenTransfer as ERC721Upgradeable doesn't use it anymore
    }
    
    /**
     * @dev Internal function to update token ownership
     * Overrides ERC721Upgradeable _update function to add KYC checks
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = super._update(to, tokenId, auth);
        
        // Skip KYC check for minting (from == 0) and burning (to == 0)
        if (from != address(0) && to != address(0)) {
            // Check if recipient is KYC verified
            if (!isAllowlisted(to)) {
                revert NotKYCVerified(to);
            }
        }
        
        return from;
    }
    
    /**
     * @dev Mints a new token to a KYC-verified address
     * @param to Address to mint the token to
     * @param tokenId ID of the token to mint
     */
    function mint(address to, uint256 tokenId) public onlyOwner {
        // Ensure recipient is KYC verified
        if (!isAllowlisted(to)) {
            revert NotKYCVerified(to);
        }
        
        _mint(to, tokenId);
    }
    
    /**
     * @dev Batch mints tokens to a KYC-verified address
     * @param to Address to mint the tokens to
     * @param tokenIds Array of token IDs to mint
     */
    function batchMint(address to, uint256[] memory tokenIds) public onlyOwner {
        // Ensure recipient is KYC verified
        if (!isAllowlisted(to)) {
            revert NotKYCVerified(to);
        }
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _mint(to, tokenIds[i]);
        }
    }
}