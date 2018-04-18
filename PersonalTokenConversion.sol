pragma solidity ^0.4.16;

import "./StableToken.sol";
import "./StandardToken.sol";
import "./Main.sol";
import "./Supplements.sol";

contract PersonalEthConversion {

  //// Main contract address
  address public mainContractAddress;
  // Supplements contract address
  address public supplementsContractAddress;
  // // Specific stable token address
  address public stableTokenAddress;
  // Specific listed token address
  address public tokenAddress;

  // Total amount of fee (in eth) stored inside the contract
  uint256 public totalTokenFee;
  // Total amount of fee (in stable tokens) stored inside the contract
  uint256 public totalStableTokenFee;
  // Timestamp of a moment when the commision was last withdrawn from the contract
  uint256 public lastTimeTokenFeeTaken;
  uint256 public lastTimeStableTokensFeeTaken;

  // Checks if the address is authorized
  modifier onlyAuthorized() {
    require(Main(mainContractAddress).authorizedAddresses(msg.sender));
    _;
  }

  // Checks if the processes are not paused
  modifier isNotPaused() {
    require(now > Main(mainContractAddress).pausedUntil());
    _;
  }

  // Checks if the person has the required amount of cPRO tokens
  modifier cProRequirement() {
    require(StandardToken(Main(mainContractAddress).cProTokenAddress()).balanceOf(msg.sender) >= Main(mainContractAddress).minCProAmount());
    _;
  }

  // Checks if stable token is activated for conversion inside Main.sol contract
  modifier activatedStableToken() {
    require(Main(mainContractAddress).activatedStableTokens(stableTokenAddress));
    _;
  }

  /**
   *  State of specific ETH collateral.
   */
  struct TokenConvert {
    // Amount of stable tokens minted by sending Eth
    uint256 stableTokens;
    // Amount of Eth sent
    uint256 collateralTokens;
  }

  /**
   *  State of specific Stables collateral.
   */
  struct ConvertCollateral {
    // Amount of stable tokens locked inside the collateral
    uint256 stableTokens;
    // Amount of derivative tokens minted for sent stables
    uint256 doesTokens;
    uint256 upesTokens;
  }

  // Mapps addresses to their collateral
  mapping (address => TokenConvert) public tokenConverts;
  mapping (address => ConvertCollateral) public convertCollaterals;

  /**
   *  Constructor function.
   *  Sets all relevant addresses.
   */
  function PersonalEthConversion(
    address _mainContractAddress,
    address _supplementsContractAddress,
    address _stableTokenAddress,
    address _tokenAddress
  ) public {
    mainContractAddress = _mainContractAddress;
    supplementsContractAddress = _supplementsContractAddress;
    stableTokenAddress = _stableTokenAddress;
    tokenAddress = _tokenAddress;
  }


  /**
   *  Exchange Eth for stable tokens at current price.
   *  Sent Eth is stored as collateral, and stable tokens are minted to msg.sender.
   */
  function buy(uint256 _amount) public isNotPaused activatedStableToken {
    require(Main(mainContractAddress).activatedStableTokens(stableTokenAddress));
    require(StandardToken(tokenAddress).transferFrom(msg.sender, this, _amount));
    // Takes current price from stable token contract
    uint256 price = StableToken(stableTokenAddress).currentPriceInToken(tokenAddress);
    // Instantiates collateral mapped to msg.sender
    TokenConvert tCollateral = tokenConverts[msg.sender];
    // Fee equals 0.2% (in Eth)
    uint256 fee = (2 * _amount) / 1000;
    // Calculates the amount of Eth to store as collateral
    uint256 toStore = _amount - fee;
    // Calculates the amount of stable tokens that should be generated
    uint256 amount = toStore / price;
    tCollateral.stableTokens += amount;
    tCollateral.collateralTokens += toStore;
    totalTokenFee += fee;
    // Interacts with Supplements.sol contract in order to update variables
    // that are used for global supplements calculation
    Supplements(supplementsContractAddress).increaseTotalCollateralTokens(toStore, tokenAddress);
    // Mints stable tokens
    StableToken(stableTokenAddress).mint(amount, msg.sender);
  }

  /**
   *  Exchange stable tokens for Eth.
   *  Only stored Eth can be repurchased this way.
   */
  function buybackTokens(uint256 _stablesAmount) public isNotPaused cProRequirement activatedStableToken {
    // Instantiates collateral mapped to msg.sender
    TokenConvert tCollateral = tokenConverts[msg.sender];
    // Takes current price from stable token contract
    uint256 price = StableToken(stableTokenAddress).currentPriceInToken(tokenAddress);
    // Calculates the maximum amount of stable tokens that can be exchanged for Eth this way
    uint256 max = tCollateral.collateralTokens / price;
    require(_stablesAmount <= max);
    // Burns sent stable tokens
    require(StableToken(stableTokenAddress).burnFrom(msg.sender, _stablesAmount));
    Supplements(supplementsContractAddress).decreaseTotalCollateralTokens(_stablesAmount * price, tokenAddress);
    // Calculates fee (0.2%)
    uint256 fee = 2 * (_stablesAmount * price) / 1000;
    // Calculates the amount of Eth to send
    uint256 toSend = _stablesAmount * price - fee;
    // Updates collateral state
    if (tCollateral.stableTokens <= _stablesAmount) {
      tCollateral.stableTokens = 0;
    }
    else {
      tCollateral.stableTokens -= _stablesAmount;
    }

    tCollateral.collateralTokens -= toSend + fee;
    // Increases total fee
    totalTokenFee += fee;
    // Sends Eth
    StandardToken(tokenAddress).transfer(msg.sender, toSend);
  }

  // Calculates the amount of non-collateralized stable tokens inside a specific address' collateral
  function personalSupplements(address _address) constant returns (uint256) {
    // Takes current price from stable token contract
    uint256 price = StableToken(stableTokenAddress).currentPriceInToken(tokenAddress);
    // Instantiates collateral mapped to msg.sender
    TokenConvert tCollateral = tokenConverts[_address];
    ConvertCollateral convCollateral = convertCollaterals[_address];

    if (tCollateral.stableTokens <= convCollateral.stableTokens) {
      return 0;
    }
    else {
      // Returns 0 if all stable tokens minted by specific token collateral are collateralized
      if (tCollateral.stableTokens - convCollateral.stableTokens <= (tCollateral.collateralTokens / price)) {
        return 0;
      }
      else {
        return tCollateral.stableTokens - convCollateral.stableTokens - (tCollateral.collateralTokens / price);
      }
    }
  }

  // Checks if DoES is available for purchase
  modifier checkForDoES() {
    // Calculates capitalization of both DoES and UpES in order to compare them
    uint256 doesCap = StandardToken(Main(mainContractAddress).doesAddress()).totalSupply() * StableToken(stableTokenAddress).currentPriceInDoES();
    uint256 upesCap = StandardToken(Main(mainContractAddress).upesAddress()).totalSupply() * StableToken(stableTokenAddress).currentPriceInUpES();
    require(doesCap <= (105 * upesCap) / 100);
    _;
  }

  // Checks if UpES is available for purchase
  modifier checkForUpES() {
    // Calculates capitalization of both DoES and UpES in order to compare them
    uint256 doesCap = StandardToken(Main(mainContractAddress).doesAddress()).totalSupply() * StableToken(stableTokenAddress).currentPriceInDoES();
    uint256 upesCap = StandardToken(Main(mainContractAddress).upesAddress()).totalSupply() * StableToken(stableTokenAddress).currentPriceInUpES();
    require(upesCap <= (105 * doesCap) / 100);
    _;
  }

  /**
   *  Buy DoES for non-collateralized stable tokens.
   *  Maximum DoES capitalization must be at least 5% lower than capitalization of UpES tokens.
   */
  function buyDoES(uint256 _stablesAmount) public checkForDoES isNotPaused activatedStableToken {
    // Supplements condition
    require((personalSupplements(msg.sender) >= _stablesAmount) || (Supplements(supplementsContractAddress).supplementsInStables(stableTokenAddress) >= _stablesAmount));
    require(StableToken(stableTokenAddress).transferFrom(msg.sender, this, _stablesAmount));
    // Calculates the amount to send
    uint256 price = StableToken(stableTokenAddress).currentPriceInDoES();
    uint256 fee = 4 * _stablesAmount / 1000;
    uint256 toSend = (_stablesAmount - fee) * price;
    // Updates total fee, stables collateral and interacts with Supplements.sol contract
    totalStableTokenFee += fee;
    convertCollaterals[msg.sender].stableTokens += _stablesAmount - fee;
    convertCollaterals[msg.sender].doesTokens += toSend;
    Supplements(supplementsContractAddress).increaseTotalStableCollateral(_stablesAmount - fee, stableTokenAddress);
    // Mints DoES tokens
    StandardToken(Main(mainContractAddress).doesAddress()).mint(toSend, msg.sender);

  }

  /**
   *  Buy UpES for non-collateralized stable tokens.
   *  Maximum UpES capitalization must be at least 5% lower than capitalization of DoES tokens.
   */
  function buyUpES(uint256 _stablesAmount) public checkForUpES isNotPaused activatedStableToken {
    // Supplements condition
    require((personalSupplements(msg.sender) >= _stablesAmount) || (Supplements(supplementsContractAddress).supplementsInStables(stableTokenAddress) >= _stablesAmount));
    require(StableToken(stableTokenAddress).transferFrom(msg.sender, this, _stablesAmount));
    // Calculates the amount to send
    uint256 price = StableToken(stableTokenAddress).currentPriceInUpES();
    uint256 fee = 4 * _stablesAmount / 1000;
    uint256 toSend = (_stablesAmount - fee) * price;
    // Updates total fee, stables collateral and interacts with Supplements.sol contract
    totalStableTokenFee += fee;
    convertCollaterals[msg.sender].stableTokens += _stablesAmount - fee;
    convertCollaterals[msg.sender].upesTokens += toSend;
    Supplements(supplementsContractAddress).increaseTotalStableCollateral(_stablesAmount - fee, stableTokenAddress);
    // Mints UpES tokens
    StandardToken(Main(mainContractAddress).upesAddress()).mint(toSend, msg.sender);

  }

  /**
   *  Buy stable tokens for DoES and/or UpES tokens.
   *  Only the amount of stable tokens that was initially exchanged for DoES and/or UpES
   *  tokens can be repurchased.
   */
  function buybackStableTokensForDoES(uint256 _doesAmount) public isNotPaused cProRequirement activatedStableToken {
    // Takes curernt DoES and UpES prices from stable token contract
    uint256 priceInDoES = StableToken(stableTokenAddress).currentPriceInDoES();
    // Calculates the amount of stable tokens to send, and calculates fee
    uint256 toSend = _doesAmount / priceInDoES;
    require(toSend <= convertCollaterals[msg.sender].doesTokens);
    // Burns sent DoES and UpES tokens
    require(StandardToken(Main(mainContractAddress).doesAddress()).burnFrom(msg.sender, _doesAmount));
    Supplements(supplementsContractAddress).decreaseTotalStableCollateral(toSend, stableTokenAddress);
    uint256 fee = 4 * toSend / 1000;
    // Updates collateral
    if (convertCollaterals[msg.sender].stableTokens <= toSend - fee) {
      convertCollaterals[msg.sender].stableTokens = 0;
    }
    else {
      convertCollaterals[msg.sender].stableTokens -= toSend - fee;
    }

    totalStableTokenFee += fee;
    // Sends stable tokens to msg.sender
    StableToken(stableTokenAddress).transfer(msg.sender, toSend - fee);
  }

  /**
   *  Buy stable tokens for DoES and/or UpES tokens.
   *  Only the amount of stable tokens that was initially exchanged for DoES and/or UpES
   *  tokens can be repurchased.
   */
  function buybackStableTokensForUpES(uint256 _upesAmount) public isNotPaused cProRequirement activatedStableToken {
    // Takes curernt DoES and UpES prices from stable token contract
    uint256 priceInUpES = StableToken(stableTokenAddress).currentPriceInUpES();
    // Calculates the amount of stable tokens to send, and calculates fee
    uint256 toSend = _upesAmount / priceInUpES;
    require(toSend <= convertCollaterals[msg.sender].upesTokens);
    // Burns sent DoES and UpES tokens
    require(StandardToken(Main(mainContractAddress).upesAddress()).burnFrom(msg.sender, _upesAmount));
    Supplements(supplementsContractAddress).decreaseTotalStableCollateral(toSend, stableTokenAddress);
    uint256 fee = 4 * toSend / 1000;
    // Updates collateral
    if (convertCollaterals[msg.sender].stableTokens <= toSend - fee) {
      convertCollaterals[msg.sender].stableTokens = 0;
    }
    else {
      convertCollaterals[msg.sender].stableTokens -= toSend - fee;
    }

    totalStableTokenFee += fee;
    // Sends stable tokens to msg.sender
    StableToken(stableTokenAddress).transfer(msg.sender, toSend - fee);
  }

  // Withdraws token fee from the contract
  // Only authorized addresses can call this function
  function withdrawTokenFee() public payable onlyAuthorized {
    uint256 amount = totalTokenFee;
    totalTokenFee = 0;
    // Sends fee to msg.sender
    StandardToken(tokenAddress).transfer(msg.sender, totalTokenFee);
    lastTimeTokenFeeTaken = now;
  }

  // Withdraws stable tokens fee from the contract
  // Only authorized addresses can call this function
  function withdrawStableTokensFee() public onlyAuthorized {
    uint256 amount = totalStableTokenFee;
    // Sends fee to msg.sender
    StableToken(stableTokenAddress).transfer(msg.sender, amount);
    lastTimeStableTokensFeeTaken = now;
  }


  function tokenConvertsAtAddress(address _address) constant returns (uint256) {
    return tokenConverts[_address].collateralTokens;
  }

  function stablesCollateralAtAddress(address _address) constant returns (uint256) {
    return convertCollaterals[_address].stableTokens;
  }

  function stablesAtAddress(address _address) constant returns (uint256) {
    return tokenConverts[_address].stableTokens;
  }



}
