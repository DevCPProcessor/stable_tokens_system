pragma solidity ^0.4.16;

import "./StableToken.sol";
import "./PersonalEthConversion.sol";
import "./PersonalTokenConversion.sol";
import "./Main.sol";

contract Interest {

  // Main.sol contract address
  address public mainContractAddress;
  // Specific stable token address
  address public stableTokenAddress;
  // PersonalEthConversion.sol contract address for specific stable token
  address public personalEthConversionAddress;

  // Addresses of all PersonalTokenConversion.sol contracts for specific stable token
  address[] public personalTokenConversionAddresses;

  // Checks if the address is authorized
  modifier onlyAuthorized() {
    require(Main(mainContractAddress).authorizedAddresses(msg.sender));
    _;
  }

  /**
   *  State of a specific deposit.
   */
  struct Deposit {
    // Amount of stable stored
    uint256 deposit;
    // Timestamp when deposit was created
    uint256 timestamp;
  }

  /**
   *  State of a specific account.
   */
  struct Account {
    // Total amount of stable stored for specific account
    uint256 totalSavings;
    // Serial number of last deposit added
    uint256 lastAdded;
    // Serial number of last deposit taken
    uint256 lastTaken;
    // Mapps serial numbers to each Deposit
    mapping (uint256 => Deposit) savings;
  }

  // Mapps each person's (contract's) address to its account
  mapping (address => Account) public accounts;

  /**
   *  Constructor function.
   *  Sets addresses of Main.sol, specific stable token and PersonalEthConversion.sol
   *  for that specific stable token.
   */
  function Interest(
    address _mainContractAddress,
    address _stableTokenAddress,
    address _personalEthConversionAddress
  ) public {
    mainContractAddress = _mainContractAddress;
    stableTokenAddress = _stableTokenAddress;
    personalEthConversionAddress = _personalEthConversionAddress;
  }

  // Sets addresses of all PersonalTokenConversion.sol contracts for specific stable token
  function setPersonalTokenConversionAddresses(address[] _personalTokenConversionAddresses) public onlyAuthorized {
    personalTokenConversionAddresses = _personalTokenConversionAddresses;
  }

  /**
   *  Sends the _amount of stable tokens to a savings account.
   *  Stable tokens are burnt, but the information about the amount and Timestamp
   *  is saved.
   */
  function save(uint256 _amount) public {
    // Reads PersonalEthConversion.sol and each PersonalTokenConversion.sol contract
    // for specific stable token in order to check the requirements
    uint256 personalEthValue = PersonalEthConversion(personalEthConversionAddress).ethConvertAtAddress(msg.sender) / StableToken(stableTokenAddress).currentPriceInEth();
    uint256 personalTokensValue;
    uint256 stablesConvertValue = PersonalEthConversion(personalEthConversionAddress).stablesConvertAtAddress(msg.sender);
    uint256 personalStables = PersonalEthConversion(personalEthConversionAddress).stablesAtAddress(msg.sender);
    for (uint i = 0; i < personalTokenConversionAddresses.length; i++) {
      personalTokensValue += PersonalTokenConversion(personalTokenConversionAddresses[i]).tokenConvertsAtAddress(msg.sender) / StableToken(stableTokenAddress).currentPriceInToken(PersonalTokenConversion(personalTokenConversionAddresses[i]).tokenAddress());
      stablesConvertValue += PersonalTokenConversion(personalTokenConversionAddresses[i]).stablesConvertAtAddress(msg.sender);
      personalStables += PersonalTokenConversion(personalTokenConversionAddresses[i]).stablesAtAddress(msg.sender);
    }

    // Checks the condition
    require(2 * personalStables >= (personalEthValue + personalTokensValue + stablesConvertValue));
    // Burns stable tokens
    require(StableToken(stableTokenAddress).burnFrom(msg.sender, _amount));

    // Updates msg.sender's account
    accounts[msg.sender].lastAdded += 1;
    accounts[msg.sender].savings[accounts[msg.sender].lastAdded].deposit = _amount;
    accounts[msg.sender].savings[accounts[msg.sender].lastAdded].timestamp = now;
    accounts[msg.sender].totalSavings += _amount;
  }


  /**
   *  Transfers stable tokens from savings account.
   *  Works by FIFO method (first deposit is transferd first).
   */
  function withdraw(uint256 _amount) public {
    // Reads from PersonalEthConversion.sol and each PersonalTokenConversion.sol for requirements
    uint256 personalEthValue = PersonalEthConversion(personalEthConversionAddress).ethConvertAtAddress(msg.sender) / StableToken(stableTokenAddress).currentPriceInEth();
    uint256 personalTokensValue;
    uint256 stablesConvertValue = PersonalEthConversion(personalEthConversionAddress).stablesConvertAtAddress(msg.sender);
    uint256 personalStables = PersonalEthConversion(personalEthConversionAddress).stablesAtAddress(msg.sender);
    for (uint i = 0; i < personalTokenConversionAddresses.length; i++) {
      personalTokensValue += PersonalTokenConversion(personalTokenConversionAddresses[i]).tokenConvertsAtAddress(msg.sender) / StableToken(stableTokenAddress).currentPriceInToken(PersonalTokenConversion(personalTokenConversionAddresses[i]).tokenAddress());
      stablesConvertValue += PersonalTokenConversion(personalTokenConversionAddresses[i]).stablesConvertAtAddress(msg.sender);
      personalStables += PersonalTokenConversion(personalTokenConversionAddresses[i]).stablesAtAddress(msg.sender);
    }

    // Checks the condition
    require(2 * personalStables <= (personalEthValue + personalTokensValue + stablesConvertValue));
    require(accounts[msg.sender].totalSavings >= _amount);

    // Calculates the interest based on each deposit's timestamp
    uint256 interest;
    uint256 toSend;
    Account account = accounts[msg.sender];
    uint256 i = account.lastTaken + 1;
    while (toSend + account.savings[i].deposit <= _amount) {
      toSend += account.savings[i].deposit;
      account.savings[i].deposit = 0;
      account.lastTaken = i;
      fee += ((now - account.savings[i].timestamp) / 10000) * account.savings[i].deposit;
      i += 1;
    }

    // `delta` will be larger than 0 if number of transfered deposits isn't an integer
    uint256 delta = _amount - toSend;
    account.savings[i].deposit -= delta;
    toSend += delta;
    fee += ((now - account.savings[i].timestamp) / 10000) * delta;

    toSend += fee;

    // Mints stable tokens (stored amount + interest)
    StableToken(stableTokenAddress).mint(toSend, msg.sender);
  }



}
