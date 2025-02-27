# User-stories

## Address User story address Base sepolia `Imple address 

0x84aC04Ff8FEEb6af6b13a8ad778FA32886b7515F

Proxy address 

0x940A3476c230B1cEf86Ac7E5caF2B70b3d48b1E0`

# PropertyToken Smart Contract Documentation

## Overview

PropertyToken is a Solidity smart contract that implements ERC-20 tokens representing fractional ownership of real estate properties. The contract is designed to be secure, gas-efficient, and upgradeable using the UUPS (Universal Upgradeable Proxy Standard) pattern.

## Features

- **Property Tokenization**: Convert real estate assets into divisible digital tokens
- **Fixed Supply**: Token supply is fixed based on property valuation
- **Upgradeability**: UUPS pattern allows for future contract upgrades
- **Security**: Implements reentrancy protection and access controls
- **Metadata Storage**: Stores property identifiers and details
- **Admin Controls**: Only the contract owner can mint tokens

## Technical Stack

- **Solidity Version**: 0.8.20 or higher
- **Framework**: OpenZeppelin Contracts Upgradeable 4.x
- **Standards**: ERC-20, ERC-1967 (Proxy)
- **Development Environment**: Remix IDE

## Contract Structure

The PropertyToken contract inherits from several OpenZeppelin base contracts:

```
PropertyToken
  ├── Initializable
  ├── ERC20Upgradeable
  ├── OwnableUpgradeable
  ├── UUPSUpgradeable
  └── ReentrancyGuardUpgradeable
```

## State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `propertyId` | string | Unique identifier for the property |
| `propertyMetadata` | string | Property details stored as JSON or IPFS hash |
| `issuer` | address | Address of the entity issuing the property tokens |
| `propertyValuation` | uint256 | Total valuation of the property in base currency |
| `fixedTokenSupply` | uint256 | Maximum number of tokens that can be minted |
| `mintedAmount` | uint256 | Number of tokens minted so far |
| `mintingCompleted` | bool | Flag indicating if minting has been finalized |

## Custom Errors

| Error | Description |
|-------|-------------|
| `MintingAlreadyCompleted` | Thrown when attempting to mint after minting is finalized |
| `NotAuthorized` | Thrown when a caller lacks permission for an operation |
| `InvalidAmount` | Thrown when an amount parameter is invalid (e.g., zero) |
| `ZeroAddress` | Thrown when an address parameter is the zero address |
| `ExceedsFixedSupply` | Thrown when a mint would exceed the fixed token supply |

## Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `PropertyOnboarded` | propertyId, metadata, totalSupply, valuation | Emitted when the contract is initialized |
| `MintingFinalized` | none | Emitted when token minting is finalized |

## Key Functions

### Initialization

```solidity
function initialize(
    string memory _name,
    string memory _symbol,
    string memory _propertyId,
    string memory _propertyMetadata,
    address _issuer,
    uint256 _propertyValuation,
    uint256 _fixedTokenSupply
) public initializer
```

Initializes the contract with property details and token parameters. Can only be called once.

**Parameters:**
- `_name`: Token name (e.g., "123 Main St Property Token")
- `_symbol`: Token symbol (e.g., "MAIN123")
- `_propertyId`: Unique identifier for the property
- `_propertyMetadata`: Property details or IPFS hash pointing to details
- `_issuer`: Address of the entity issuing the tokens
- `_propertyValuation`: Total property value in base currency
- `_fixedTokenSupply`: Maximum number of tokens that can be minted

### Token Minting

```solidity
function mintPropertyTokens(address _to, uint256 _amount) 
    external 
    onlyOwner 
    nonReentrant
```

Mints tokens to the specified address, subject to the fixed supply constraint.

**Parameters:**
- `_to`: Recipient address
- `_amount`: Number of tokens to mint

**Restrictions:**
- Only callable by the contract owner
- Cannot be called after minting is finalized
- Cannot exceed the fixed token supply

### Minting Finalization

```solidity
function finalizeMinting() external onlyOwner
```

Permanently prevents any further token minting. Can only be called by the contract owner.

### Metadata Update

```solidity
function updatePropertyMetadata(string memory _newMetadata) 
    external 
    onlyOwner
```

Updates the property metadata. Can only be called by the contract owner.

**Parameters:**
- `_newMetadata`: New property metadata string or IPFS hash

### View Functions

```solidity
function remainingSupply() external view returns (uint256)
```
Returns the number of tokens that can still be minted before reaching the fixed supply.

```solidity
function tokenValue() external view returns (uint256)
```
Returns the value of a single token in relation to the property valuation.

```solidity
function getPropertyDetails() external view returns (
    string memory _propertyId,
    address _issuer,
    uint256 _totalSupply,
    uint256 _mintedAmount,
    uint256 _propertyValuation
)
```
Returns all property and token supply details in a single call.

## Upgrade Mechanism

The contract uses the UUPS pattern for upgradeability:

```solidity
function _authorizeUpgrade(address newImplementation) 
    internal 
    override 
    onlyOwner
```

This function must be overridden to authorize contract upgrades. Only the contract owner can perform upgrades.

## ERC-20 Token Details

The contract implements the standard ERC-20 interface:
- `balanceOf(address)`: Check token balance
- `transfer(address, uint256)`: Transfer tokens
- `transferFrom(address, address, uint256)`: Transfer tokens on behalf of another
- `approve(address, uint256)`: Approve token spending
- `allowance(address, address)`: Check spending allowance

For real estate tokens, the contract overrides the default `decimals()` function:

```solidity
function decimals() public view virtual override returns (uint8) {
    return 6;
}
```

This sets 6 decimal places (rather than 18) for more intuitive property valuations.

## Deployment Process

### Step 1: Deploy Implementation Contract

Deploy the PropertyToken implementation contract (without initializing it).

### Step 2: Deploy Proxy

Deploy an ERC1967Proxy contract with:
- Implementation address
- Initialization data (ABI-encoded call to `initialize` function)

### Step 3: Interact with Proxy

All interactions should be with the proxy address using the PropertyToken ABI.

## Example Deployment Using PropertyTokenDeployer

```solidity
// Deploy implementation contract
PropertyToken implementation = new PropertyToken();

// Deploy deployer contract
PropertyTokenDeployer deployer = new PropertyTokenDeployer();

// Prepare initialization data
bytes memory initData = abi.encodeWithSignature(
    "initialize(string,string,string,string,address,uint256,uint256)",
    "123 Main St Property Token",
    "MAIN123",
    "PROP-001",
    "{\"address\":\"123 Main St\",\"size\":\"2000sqft\",\"type\":\"residential\"}",
    0x123...456, // Issuer address
    1000000000000, // $1M valuation (with 6 decimal places)
    1000000 // 1M tokens
);

// Deploy proxy
address proxy = deployer.deployPropertyTokenProxy(
    address(implementation),
    initData
);

// Interact with proxy using PropertyToken ABI
PropertyToken tokenContract = PropertyToken(proxy);
```

## Security Considerations

- **Reentrancy Protection**: All external functions are protected with the `nonReentrant` modifier.
- **Access Controls**: Critical functions are restricted to the contract owner.
- **Supply Caps**: Token minting is restricted by the fixed supply.
- **Upgrades**: Only the owner can authorize contract upgrades.
- **Error Handling**: Custom errors provide clear failure reasons while optimizing gas.

## Gas Optimization

- Uses custom errors instead of require statements
- Optimizes function visibility
- Follows best practices for state variable packing
- Implements efficient upgrade pattern (UUPS vs Transparent Proxy)

## Best Practices

- Initialize all variables in the `initialize` function
- Emit events for important state changes
- Implement proper access controls
- Follow checks-effects-interactions pattern
- Use nonReentrant guards for external functions
- Document all functions and state variables
