pragma solidity ^0.4.16;

import "./erc20.sol";
import "./StableToken.sol";

contract PersonalEthCollateral {

  // Total amount of fee stored inside the contract
  uint256 public totalFee;
  // Timestamp of a moment when the commision was last withdrawn from the contract
  uint256 public lastTimeFeeTaken;
  // Fee percentage that goes to oracle wallet
  uint256 public oraclePercent;
  // Minimum amount of cPRO tokens one must have in order to call certain functions
  uint256 public minCProAmount;

  // Stable token address
  address public stableTokenAddress;
  // Oracle wallet address
  address public oracleWalletAddress;
  // Buyback contract address
  address public buybackContractAddress;
  // cPRO token address
  address public cProContractAddress;

  // This creates a mapping of authorized addresses
  mapping (address => bool) public authorizedAddresses;

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

  /**
   * State of one collateral.
   */
  struct EthCollateral {
    // Amount of stable tokens minted when transaction occured
    uint256 amountOfCollateralStables;
    // Amount of ether exchanged for stable tokens
    uint256 amountOfCollateralEth;
    // Timestamp of a moment when transaction occured
    uint256 collateralTimestamp;
  }

  /**
   * Specific address' collateral profile.
   */
  struct EthCollateralProfile {
    // TotaL number of collaterals address owns
    uint256 numberOfEthCollaterals;
    // Total amount of stable tokens bought "with collateral"
    uint256 totalCollateralStables;
    // Total amount of ether exchanged for tokens "with collateral"
    uint256 totalCollateralEth;
    // Serial number of the last added collateral
    uint256 lastCollateralAdded;
    // Serial number of the last taken collateral
    uint256 lastCollateralTaken;
    // Mapps serial number to specific collateral
    mapping (uint256 => EthCollateral) ethCollaterals;
  }

  // Mapps addresses to their collateral profiles
  mapping (address => EthCollateralProfile) public ethCollateralProfiles;

  /**
   *  Constructor function.
   *  Sets addresses of necessary contracts.
   */
  function PersonalEthCollateral(
    address _stableTokenAddress,
    address _oracleWalletAddress,
    address _buybackContractAddress,
    address _cProContractAddress
  ) public {
    stableTokenAddress = _stableTokenAddress;
    oracleWalletAddress = _oracleWalletAddress;
    buybackContractAddress = _buybackContractAddress;
    cProContractAddress = _cProContractAddress;
  }

  // Changes the oracle wallet address
  // Can only be called by authorized addressess
  function changeOracleWalletAddress(address _newAddress) public onlyAuthorized {
    oracleWalletAddress = _newAddress;
  }

  // Changes the commision percentage that goes to oracle
  // Can only be called by authorized addresses
  function changeOraclePercent(uint256 _newPercent) public onlyAuthorized {
    require(_newPercent <= 100);
    oraclePercent = _newPercent;
  }

  // Sends fee from the contract to oracle and buyback contract
  function withdrawFee() public payable onlyAuthorized {
    uint256 amountForOracle = (totalFee * oraclePercent) / 100;
    uint256 amountForBuyback = totalFee - amountForOracle;
    totalFee = 0;
    oracleWalletAddress.transfer(amountForOracle);
    buybackContractAddress.transfer(amountForBuyback);
    lastTimeFeeTaken = now;
  }

  // Sets the minimum amount of cPRO tokens one must have in order to call certain functions
  // Can only be called by authorized addresses
  function setMinCProAmount(uint256 _newAmount) public onlyAuthorized {
    minCProAmount = _newAmount;
  }

  // Fallback function
  function () public payable {
    buy();
  }

  /**
   * Buy stable tokens and store sent ethereum as collateral. Later, funds can be
   * recovered in exchange for same amount of minted tokens.
   */
  function buy() public payable isNotPaused {
    require(msg.value > 0);
    // Conversion fee
    uint256 fee = (5 * msg.value) / 1000;
    uint256 toStore = msg.value - fee;
    uint256 price = StableToken(stableTokenAddress).currentPriceInEth();
    // Calculates the amount
    uint256 amount = toStore / price;
    totalFee += fee;

    // Creates an instance of msg.sender's collateral profile
    EthCollateralProfile profile = ethCollateralProfiles[msg.sender];
    // Increases msg.sender's total number of collaterals
    profile.numberOfEthCollaterals += 1;
    // Increases msg.sender's total amount of stable tokens bought "with collateral"
    profile.totalCollateralStables += amount;
    // Increases msg.sender's total amount of ether stored as collateral
    profile.totalCollateralEth += toStore;
    // Remembers the serial number of last collateral added
    profile.lastCollateralAdded += 1;

    // Creates an instance of this specific collateral
    EthCollateral collateral = profile.ethCollaterals[profile.lastCollateralAdded];
    // Remembers the amount of stable tokens minted with this collateral
    collateral.amountOfCollateralStables = amount;
    // Remembers the amount of ether stored as this specific collateral
    collateral.amountOfCollateralEth = toStore;
    // Remembers the timestamp of conversion
    collateral.collateralTimestamp = now;

    // Mints stable tokens
    StableToken(stableTokenAddress).mint(amount, msg.sender);
  }

  /**
   * Exchange stable tokens for ether stored as collateral.
   * Ethers are distributed by FIFO method.
   */
  function takeFromPersonalCollateral(uint256 _stablesAmount) public payable cProRequirement isNotPaused {
    require(ethCollateralProfiles[msg.sender].totalCollateralStables >= _stablesAmount);
    require(StableToken(stableTokenAddress).additionalBurn(_stablesAmount, msg.sender));
    uint256 fee = 0;
    EthCollateralProfile profile = ethCollateralProfiles[msg.sender];
    uint256 ethToReturn = 0;
    uint256 amount = 0;

    // Sets numerator
    uint256 index = profile.lastCollateralTaken + 1;
    uint256 Days;

    // Iterates through collaterals starting from the oldest one
    // in order to calculate how much ether to send
    while ((amount + profile.ethCollaterals[index].amountOfCollateralStables) < _stablesAmount) {
      amount += profile.ethCollaterals[index].amountOfCollateralStables;
      profile.totalCollateralStables -= profile.ethCollaterals[index].amountOfCollateralStables;
      profile.ethCollaterals[index].amountOfCollateralStables = 0;

      ethToReturn += profile.ethCollaterals[index].amountOfCollateralEth;
      Days = (now - profile.ethCollaterals[index].collateralTimestamp) / 86400;
      // Daily fee equals 0.01% of the initial collateral ethers
      if ((((Days + 1) * profile.ethCollaterals[index].amountOfCollateralEth) / 10000) > profile.ethCollaterals[index].amountOfCollateralEth) {
        fee += profile.ethCollaterals[index].amountOfCollateralEth;
      }
      else {
        fee += ((Days + 1) * profile.ethCollaterals[index].amountOfCollateralEth) / 10000;
      }

      // Decreases total amount of stored ether
      profile.totalCollateralEth -= profile.ethCollaterals[index].amountOfCollateralEth;
      profile.ethCollaterals[index].amountOfCollateralEth = 0;
      // If specific collateral is drawn, decreases the total collateral number
      profile.numberOfEthCollaterals -= 1;
      index += 1;
    }

    // If number of drawn collaterals is not an integer
    // calculates the residue
    uint256 delta = _StablesAmount - amount;
    amount += delta;
    profile.totalCollateralStables -= delta;
    uint256 ethFromDelta = (profile.ethCollaterals[index].amountOfCollateralEth * delta) / profile.ethCollaterals[index].amountOfCollateralStables;
    ethToReturn += ethFromDelta;

    Days = (now - profile.ethCollaterals[index].collateralTimestamp) / 86400;
    if ((((Days + 1) * ethFromDelta) / 10000) > ethFromDelta) {
      fee += ethFromDelta;
    }
    else {
      fee += ((Days + 1) * ethFromDelta) / 10000;
    }

    profile.totalCollateralEth -= (profile.ethCollaterals[index].amountOfCollateralEth * delta) / profile.ethCollaterals[index].amountOfCollateralStables;
    profile.ethCollaterals[index].amountOfCollateralEth -= (profile.ethCollaterals[index].amountOfCollateralEth * delta) / profile.ethCollaterals[index].amountOfCollateralStables;
    profile.ethCollaterals[index].amountOfCollateralStables -= delta;

    if (profile.ethCollaterals[index].amountOfCollateralStables == 0) {
      profile.lastCollateralTaken = index;
      profile.numberOfEthCollaterals -= 1;
    }
    else {
      profile.lastCollateralTaken = index - 1;
    }

    // Sends ether to msg.sender
    msg.sender.transfer(ethToReturn - fee);
    // Increases total collateral fee
    totalFee += fee;

  }



  // Functions for informational purposes
  function getSpecificCollateralStables(address _collateralSuperAdmin, uint256 index) constant returns (uint256) {
    return ethCollateralProfiles[_collateralSuperAdmin].ethCollaterals[index].amountOfCollateralStables;
  }
  function getSpecificCollateralEth(address _collateralSuperAdmin, uint256 index) constant returns (uint256) {
    return ethCollateralProfiles[_collateralSuperAdmin].ethCollaterals[index].amountOfCollateralEth;
  }
  function getSpecificCollateralTimestamp(address _collateralSuperAdmin, uint256 index) constant returns (uint256) {
    return ethCollateralProfiles[_collateralSuperAdmin].ethCollaterals[index].collateralTimestamp;
  }


}
