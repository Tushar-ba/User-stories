// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title PropertyToken
 * @dev ERC20 token representing fractional ownership of a real estate property
 * Implements UUPS upgradeable pattern and ReentrancyGuard for security
 */
contract PropertyToken is 
    Initializable, 
    ERC20Upgradeable, 
    OwnableUpgradeable, 
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable 
{
    /// @notice Unique identifier for the property
    string public propertyId;
    
    /// @notice Property details stored as JSON string (could be IPFS hash in production)
    string public propertyMetadata;
    
    /// @notice Address of the issuer of the property tokens
    address public issuer;
    
    /// @notice Fixed total supply based on property valuation
    uint256 public propertyValuation;
    
    /// @notice Total supply of tokens to be minted
    uint256 public fixedTokenSupply;
    
    /// @notice Amount already minted
    uint256 public mintedAmount;
    
    /// @notice Boolean flag to track if initial minting has completed
    bool public mintingCompleted;

    /// @notice Custom errors for gas efficiency
    error MintingAlreadyCompleted();
    error NotAuthorized();
    error InvalidAmount();
    error ZeroAddress();
    error ExceedsFixedSupply();

    /// @notice Events for important state changes
    event PropertyOnboarded(string propertyId, string metadata, uint256 totalSupply, uint256 valuation);
    event MintingFinalized();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with property details and token parameters
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _propertyId Unique identifier for the property
     * @param _propertyMetadata Property details (JSON string or IPFS hash)
     * @param _issuer Address of the entity issuing the property tokens
     * @param _propertyValuation The total valuation of the property in base currency
     * @param _fixedTokenSupply The fixed total supply of tokens that can ever be minted
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _propertyId,
        string memory _propertyMetadata,
        address _issuer,
        uint256 _propertyValuation,
        uint256 _fixedTokenSupply
    ) public initializer {
        if (_issuer == address(0)) revert ZeroAddress();
        if (_propertyValuation == 0) revert InvalidAmount();
        if (_fixedTokenSupply == 0) revert InvalidAmount();
        
        __ERC20_init(_name, _symbol);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        propertyId = _propertyId;
        propertyMetadata = _propertyMetadata;
        issuer = _issuer;
        propertyValuation = _propertyValuation;
        fixedTokenSupply = _fixedTokenSupply;
        mintedAmount = 0;
        mintingCompleted = false;
        
        emit PropertyOnboarded(_propertyId, _propertyMetadata, _fixedTokenSupply, _propertyValuation);
    }

    /**
     * @dev Mints tokens to represent property shares within the fixed supply limit
     * @param _to Address to receive the tokens
     * @param _amount Amount of tokens to mint
     * Requirements:
     * - Can only be called by the contract owner
     * - Minting must not be completed
     * - Cannot exceed fixed supply
     */
    function mintPropertyTokens(address _to, uint256 _amount) 
        external 
        onlyOwner 
        nonReentrant 
    {
        if (mintingCompleted) revert MintingAlreadyCompleted();
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert InvalidAmount();
        if (mintedAmount + _amount > fixedTokenSupply) revert ExceedsFixedSupply();
        
        mintedAmount += _amount;
        _mint(_to, _amount);
        
        // Auto-finalize if we've reached the fixed supply
        if (mintedAmount == fixedTokenSupply) {
            mintingCompleted = true;
            emit MintingFinalized();
        }
    }

    /**
     * @dev Finalizes the minting process, preventing further token creation
     * Can only be called by the contract owner
     */
    function finalizeMinting() external onlyOwner {
        mintingCompleted = true;
        emit MintingFinalized();
    }

    /**
     * @dev Updates the property metadata
     * @param _newMetadata New metadata for the property
     * Requirements:
     * - Can only be called by the contract owner
     */
    function updatePropertyMetadata(string memory _newMetadata) 
        external 
        onlyOwner 
    {
        propertyMetadata = _newMetadata;
    }

    /**
     * @dev Required by the UUPS pattern to authorize upgrades
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
    {}

    /**
     * @dev Overrides the decimals function to return 6 instead of default 18
     * Using 6 decimals is more appropriate for real estate tokens
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    /**
     * @dev Gets the remaining tokens that can be minted
     * @return The remaining tokens that can be minted
     */
    function remainingSupply() external view returns (uint256) {
        return fixedTokenSupply - mintedAmount;
    }
    
    /**
     * @dev Returns the token value in relation to the property valuation
     * @return The value of a single token in base currency
     */
    function tokenValue() external view returns (uint256) {
        return propertyValuation / fixedTokenSupply;
    }
    
    /**
     * @dev Returns detailed information about the property token
     * @return _propertyId The property identifier
     * @return _issuer The address of the token issuer
     * @return _totalSupply The fixed total supply
     * @return _mintedAmount The amount already minted
     * @return _propertyValuation The total property valuation
     */
    function getPropertyDetails() external view returns (
        string memory _propertyId,
        address _issuer,
        uint256 _totalSupply,
        uint256 _mintedAmount,
        uint256 _propertyValuation
    ) {
        return (
            propertyId,
            issuer,
            fixedTokenSupply,
            mintedAmount,
            propertyValuation
        );
    }
}