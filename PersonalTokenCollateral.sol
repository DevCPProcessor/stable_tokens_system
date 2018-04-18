pragma solidity ^0.4.16;

import "./erc20.sol";
import "./StableToken.sol";

contract PersonalTokenCollateral {

  // Total amount of fee stored inside the contract for each token
  mapping (address => uint256) public totalTokenFee;
  // Timestamp of a moment when the commision was last withdrawn from the contract for each token
  mapping (address => uint256) public lastTimeTokenFeeTaken;
  // Timestamp of a moment when the commision was last withdrawn from the contract for each token
  uint256 public minCProAmount;

  // Stable token address
  address public stableTokenAddress;
  // cPRO token address
  address public cProContractAddress;

  // This creates a mapping of authorized addresses
  mapping (address => bool) public authorizedAddresses;
  // This creates a mapping of listed tokens
  mapping (address => bool) public listedTokens;

  // Authorizes other addresses
  function authorize(address _address) public onlySuperAdmin {
    authorizedAddresses[_address] = true;
  }

  // Unauthorizes other addresses
  function unauthorize(address _address) public onlySuperAdmin {
    authorizedAddresses[_address] = false;
  }

  // Checks if the address is authorized
  modifier onlyAuthorized() {
    require(authorizedAddresses[msg.sender]);
    _;
  }

  // Checks if the address is superAdmin's address
  modifier onlySuperAdmin() {
    require(msg.sender == StableToken(stableTokenAddress).superAdmin());
    _;
  }

  // Checks if the processes are not paused
  modifier isNotPaused() {
    require(now > StableToken(stableTokenAddress).pausedUntil());
    _;
  }

  // Checks if the person has the required amount of cPRO tokens
  modifier cProRequirement() {
    require(ERC20Interface(cProContractAddress).balanceOf(msg.sender) >= minCProAmount);
    _;
  }

  // Lists token
  // Can only be called by authorized addresses
  function listToken(address _tokenAddress) public onlyAuthorized {
    require(!listedTokens[_tokenAddress]);
    listedTokens[_tokenAddress] = true;
  }

  // Unlists token
  // Can only be called by authorized addresses
  function unlistToken(address _tokenAddress) public onlyAuthorized {
    require(listedTokens[_tokenAddress]);
    listedTokens[_tokenAddress] = false;
  }

  // Sets the minimum amount of cPRO tokens one must have in order to call certain functions
  // Can only be called by authorized addresses
  function setMinCProAmount(uint256 _newAmount) public onlyAuthorized {
    minCProAmount = _newAmount;
  }

  /**
   *  Constructor function.
   *  Sets addresses of necessary contracts.
   */
  function PersonalTokenCollateral(
    address _stableTokenAddress,
    address _cProContractAddress
  ) public {
    stableTokenAddress = _stableTokenAddress;
    cProContractAddress = _cProContractAddress;
  }

  /**
   * State of one collateral.
   */
  struct TokenCollateral {
    // Amount of stable tokens minted when transaction occured
    uint256 amountOfCollateralStables;
    // Amount of tokens exchanged for stable tokens
    uint256 amountOfCollateralTokens;
    // Timestamp of a moment when transaction occured
    uint256 collateralTimestamp;
  }

  /**
   * Specific address' collateral profile.
   */
  struct TokenCollateralProfile {
    // TotaL number of collaterals address owns
    uint256 numberOfCollaterals;
    // Total amount of stable tokens bought "with collateral"
    uint256 totalCollateralStables;
    // Total amount of ether exchanged for tokens "with collateral"
    uint256 totalCollateralTokens;
    // Serial number of the last added collateral
    uint256 lastCollateralAdded;
    // Serial number of the last taken collateral
    uint256 lastCollateralTaken;
    // Mapps serial number to specific collateral
    mapping (uint256 => TokenCollateral) tokenCollaterals;
  }

  // Set of specific address' collateral profiles
  mapping (address => mapping (address => TokenCollateralProfile)) public setOfProfiles;

  /**
   * Buy stable tokens and store sent tokens as collateral. Later, funds can be
   * recovered in exchange for same amount of minted tokens.
   */
  function buy(address _tokenAddress, uint256 _tokenAmount) public isNotPaused {
    require(listedTokens[_tokenAddress]);
    require(ERC20Interface(_tokenAddress).transferFrom(msg.sender, this, _tokenAmount));
    // Conversion fee
    uint256 fee = (5 * _tokenAmount) / 1000;
    uint256 toStore = _tokenAmount - fee;
    uint256 price = StableToken(stableTokenAddress).currentPriceInToken(_tokenAddress);
    // Calculates the amount
    uint256 amount = toStore / price;
    totalTokenFee[_tokenAddress] += fee;

    // Creates an instance of msg.sender's collateral profile
    TokenCollateralProfile profile = setOfProfiles[msg.sender][_tokenAddress];
    // Increases msg.sender's total number of collaterals
    profile.numberOfCollaterals += 1;
    // Increases msg.sender's total amount of stable tokens bought "with collateral"
    profile.totalCollateralStables += amount;
    // Increases msg.sender's total amount of tokens stored as collateral
    profile.totalCollateralTokens += toStore;
    // Remembers the serial number of last collateral added
    profile.lastCollateralAdded += 1;

    // Creates an instance of this specific collateral
    TokenCollateral collateral = profile.tokenCollaterals[profile.lastCollateralAdded];
    // Remembers the amount of stable tokens minted with this collateral
    collateral.amountOfCollateralStables = amount;
    // Remembers the amount of tokens stored as this specific collateral
    collateral.amountOfCollateralTokens = toStore;
    // Remembers the timestamp of conversion
    collateral.collateralTimestamp = now;

    // Mints stable tokens
    StableToken(stableTokenAddress).mint(amount, msg.sender);
  }

  /**
   * Exchange stable tokens for tokens stored as collateral.
   * Tokens are distributed by FIFO method.
   */
  function takeTokenCollateral(address _tokenAddress, uint256 _stablesAmount) public cProRequirement isNotPaused {
    require(setOfProfiles[msg.sender][_tokenAddress].totalCollateralStables >= _stablesAmount);
    require(StableToken(stableTokenAddress).additionalBurn(_stablesAmount, msg.sender));
    uint256 fee = 0;
    TokenCollateralProfile profile = setOfProfiles[msg.sender][_tokenAddress];
    uint256 toReturn = 0;
    uint256 amount = 0;

    // Sets numerator
    uint256 index = profile.lastCollateralTaken + 1;
    uint256 Days;

    // Iterates through collaterals starting from the oldest one
    // in order to calculate how much tokens to send
    while ((amount + profile.tokenCollaterals[index].amountOfCollateralStables) < _stablesAmount) {
      amount += profile.tokenCollaterals[index].amountOfCollateralStables;
      profile.totalCollateralStables -= profile.tokenCollaterals[index].amountOfCollateralStables;
      profile.tokenCollaterals[index].amountOfCollateralStables = 0;

      toReturn += profile.tokenCollaterals[index].amountOfCollateralTokens;
      Days = (now - profile.tokenCollaterals[index].collateralTimestamp) / 86400;
      // Daily fee equals 0.01% of the initial collateral tokens
      if ((((Days + 1) * profile.tokenCollaterals[index].amountOfCollateralTokens) / 10000) > profile.tokenCollaterals[index].amountOfCollateralTokens) {
        fee += profile.tokenCollaterals[index].amountOfCollateralTokens;
      }
      else {
        fee += ((Days + 1) * profile.tokenCollaterals[index].amountOfCollateralTokens) / 10000;
      }

      // Decreases total amount of stored tokens
      profile.totalCollateralTokens -= profile.tokenCollaterals[index].amountOfCollateralTokens;
      profile.tokenCollaterals[index].amountOfCollateralTokens = 0;
      // If specific collateral is drawn, decreases the total collateral number
      profile.numberOfCollaterals -= 1;
      index += 1;
    }

    // If number of drawn collaterals is not an integer
    // calculates the residue
    uint256 delta = _stablesAmount - amount;
    amount += delta;
    profile.totalCollateralStables -= delta;
    uint256 fromDelta = (profile.tokenCollaterals[index].amountOfCollateralTokens * delta) / profile.tokenCollaterals[index].amountOfCollateralStables;
    toReturn += fromDelta;

    Days = (now - profile.tokenCollaterals[index].collateralTimestamp) / 86400;
    if ((((Days + 1) * fromDelta) / 10000) > fromDelta) {
      fee += fromDelta;
    }
    else {
      fee += ((Days + 1) * fromDelta) / 10000;
    }

    profile.totalCollateralTokens -= (profile.tokenCollaterals[index].amountOfCollateralTokens * delta) / profile.tokenCollaterals[index].amountOfCollateralStables;
    profile.tokenCollaterals[index].amountOfCollateralTokens -= (profile.tokenCollaterals[index].amountOfCollateralTokens * delta) / profile.tokenCollaterals[index].amountOfCollateralStables;
    profile.tokenCollaterals[index].amountOfCollateralStables -= delta;

    if (profile.tokenCollaterals[index].amountOfCollateralStables == 0) {
      profile.lastCollateralTaken = index;
      profile.numberOfCollaterals -= 1;
    }
    else {
      profile.lastCollateralTaken = index - 1;
    }

    // Sends tokens to msg.sender
    ERC20Interface(_tokenAddress).transfer(msg.sender, toReturn - fee);
    // Increases total collateral fee
    totalTokenFee[_tokenAddress] += fee;
  }

  // Sends fee from the contract to msg.sender's address
  // Can only be called by authorized addresses
  function withdrawTokenFee(address _tokenAddress) public onlyAuthorized {
    uint256 amount = totalTokenFee[_tokenAddress];
    totalTokenFee[_tokenAddress] = 0;
    ERC20Interface(_tokenAddress).transfer(msg.sender, amount);
    lastTimeTokenFeeTaken[_tokenAddress] = now;
  }


  // Functions for informational purposes
  function getSpecificCollateralStables(address _tokenAddress, address _collateralSuperAdmin, uint256 index) constant returns (uint256) {
    return setOfProfiles[_collateralSuperAdmin][_tokenAddress].tokenCollaterals[index].amountOfCollateralStables;
  }
  function getSpecificCollateralTokens(address _tokenAddress, address _collateralSuperAdmin, uint256 index) constant returns (uint256) {
    return setOfProfiles[_collateralSuperAdmin][_tokenAddress].tokenCollaterals[index].amountOfCollateralTokens;
  }
  function getSpecificCollateralTimestamp(address _tokenAddress, address _collateralSuperAdmin, uint256 index) constant returns (uint256) {
    return setOfProfiles[_collateralSuperAdmin][_tokenAddress].tokenCollaterals[index].collateralTimestamp;
  }

}
