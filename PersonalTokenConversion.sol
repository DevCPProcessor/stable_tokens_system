pragma solidity ^0.4.16;

import "./StableToken.sol";
import "./StandardToken.sol";
import "./Main.sol";
import "./Supplements.sol";

contract PersonalTokenConversion {

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
   *  State of specific ETH convert.
   */
  struct TokenConvert {
    // Amount of stable tokens minted by sending Eth
    uint256 stableTokens;
    // Amount of Eth sent
    uint256 convertTokens;
  }

  /**
   *  State of specific Stables convert.
   */
  struct StableConvert {
    // Amount of stable tokens locked inside the convert
    uint256 stableTokens;
    // Amount of derivative tokens minted for sent stables
    uint256 doesTokens;
    uint256 upesTokens;
  }

  // Mapps addresses to their convert
  mapping (address => TokenConvert) public tokenConverts;
  mapping (address => StableConvert) public stableConverts;

  /**
   *  Constructor function.
   *  Sets all relevant addresses.
   */
  function PersonalTokenConversion(
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
   *  Sent Eth is stored as convert, and stable tokens are minted to msg.sender.
   */
  function buy(uint256 _amount) public isNotPaused activatedStableToken {
    require(Main(mainContractAddress).activatedStableTokens(stableTokenAddress));
    require(StandardToken(tokenAddress).transferFrom(msg.sender, this, _amount));
    // Takes current price from stable token contract
    uint256 price = StableToken(stableTokenAddress).currentPriceInToken(tokenAddress);
    // Instantiates convert mapped to msg.sender
    TokenConvert tConvert = tokenConverts[msg.sender];
    // Fee equals 0.2% (in Eth)
    uint256 fee = (2 * _amount) / 1000;
    // Calculates the amount of Eth to store as convert
    uint256 toStore = _amount - fee;
    // Calculates the amount of stable tokens that should be generated
    uint256 amount = toStore / price;
    tConvert.stableTokens += amount;
    tConvert.convertTokens += toStore;
    totalTokenFee += fee;
    // Interacts with Supplements.sol contract in order to update variables
    // that are used for global supplements calculation
    Supplements(supplementsContractAddress).increaseTotalConvertTokens(toStore, tokenAddress);
    // Mints stable tokens
    StableToken(stableTokenAddress).mint(amount, msg.sender);
  }

  /**
   *  Exchange stable tokens for Eth.
   *  Only stored Eth can be repurchased this way.
   */
  function buybackTokens(uint256 _stablesAmount) public isNotPaused cProRequirement activatedStableToken {
    // Instantiates convert mapped to msg.sender
    TokenConvert tConvert = tokenConverts[msg.sender];
    // Takes current price from stable token contract
    uint256 price = StableToken(stableTokenAddress).currentPriceInToken(tokenAddress);
    // Calculates the maximum amount of stable tokens that can be exchanged for Eth this way
    uint256 max = tConvert.convertTokens / price;
    require(_stablesAmount <= max);
    // Burns sent stable tokens
    require(StableToken(stableTokenAddress).burnFrom(msg.sender, _stablesAmount));
    Supplements(supplementsContractAddress).decreaseTotalConvertTokens(_stablesAmount * price, tokenAddress);
    // Calculates fee (0.2%)
    uint256 fee = 2 * (_stablesAmount * price) / 1000;
    // Calculates the amount of Eth to send
    uint256 toSend = _stablesAmount * price - fee;
    // Updates convert state
    if (tConvert.stableTokens <= _stablesAmount) {
      tConvert.stableTokens = 0;
    }
    else {
      tConvert.stableTokens -= _stablesAmount;
    }

    tConvert.convertTokens -= toSend + fee;
    // Increases total fee
    totalTokenFee += fee;
    // Sends Eth
    StandardToken(tokenAddress).transfer(msg.sender, toSend);
  }

  // Calculates the amount of non-convertalized stable tokens inside a specific address' convert
  function personalSupplements(address _address) constant returns (uint256) {
    // Takes current price from stable token contract
    uint256 price = StableToken(stableTokenAddress).currentPriceInToken(tokenAddress);
    // Instantiates convert mapped to msg.sender
    TokenConvert tConvert = tokenConverts[_address];
    StableConvert convConvert = convertConverts[_address];

    if (tConvert.stableTokens <= convConvert.stableTokens) {
      return 0;
    }
    else {
      // Returns 0 if all stable tokens minted by specific token convert are convertalized
      if (tConvert.stableTokens - convConvert.stableTokens <= (tConvert.convertTokens / price)) {
        return 0;
      }
      else {
        return tConvert.stableTokens - convConvert.stableTokens - (tConvert.convertTokens / price);
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
   *  Buy DoES for non-convertalized stable tokens.
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
    // Updates total fee, stables convert and interacts with Supplements.sol contract
    totalStableTokenFee += fee;
    convertConverts[msg.sender].stableTokens += _stablesAmount - fee;
    convertConverts[msg.sender].doesTokens += toSend;
    Supplements(supplementsContractAddress).increaseTotalStableConvert(_stablesAmount - fee, stableTokenAddress);
    // Mints DoES tokens
    StandardToken(Main(mainContractAddress).doesAddress()).mint(toSend, msg.sender);

  }

  /**
   *  Buy UpES for non-convertalized stable tokens.
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
    // Updates total fee, stables convert and interacts with Supplements.sol contract
    totalStableTokenFee += fee;
    stableConverts[msg.sender].stableTokens += _stablesAmount - fee;
    stableConverts[msg.sender].upesTokens += toSend;
    Supplements(supplementsContractAddress).increaseTotalStableConvert(_stablesAmount - fee, stableTokenAddress);
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
    require(toSend <= stableConverts[msg.sender].doesTokens);
    // Burns sent DoES and UpES tokens
    require(StandardToken(Main(mainContractAddress).doesAddress()).burnFrom(msg.sender, _doesAmount));
    Supplements(supplementsContractAddress).decreaseTotalStableConvert(toSend, stableTokenAddress);
    uint256 fee = 4 * toSend / 1000;
    // Updates convert
    if (stableConverts[msg.sender].stableTokens <= toSend - fee) {
      stableConverts[msg.sender].stableTokens = 0;
    }
    else {
      stableConverts[msg.sender].stableTokens -= toSend - fee;
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
    require(toSend <= stableConverts[msg.sender].upesTokens);
    // Burns sent DoES and UpES tokens
    require(StandardToken(Main(mainContractAddress).upesAddress()).burnFrom(msg.sender, _upesAmount));
    Supplements(supplementsContractAddress).decreaseTotalStableConvert(toSend, stableTokenAddress);
    uint256 fee = 4 * toSend / 1000;
    // Updates convert
    if (stableConverts[msg.sender].stableTokens <= toSend - fee) {
      stableConverts[msg.sender].stableTokens = 0;
    }
    else {
      stableConverts[msg.sender].stableTokens -= toSend - fee;
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
    return tokenConverts[_address].convertTokens;
  }

  function stablesConvertAtAddress(address _address) constant returns (uint256) {
    return stableConverts[_address].stableTokens;
  }

  function stablesAtAddress(address _address) constant returns (uint256) {
    return tokenConverts[_address].stableTokens;
  }



}
