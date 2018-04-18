pragma solidity ^0.4.16;

import "./StableToken.sol";
import "./Main.sol";

contract Forex {

  address public mainContractAddress;

  // Stable tokens' addresses
  address public dotoAddress;
  address public eutoAddress;
  address public krtoAddress;
  address public yetoAddress;
  address public yutoAddress;

  // Mapps each token to its fee
  mapping (address => uint256) public fees;

  // Mapps each stable token to "true" if token is available for conversion, to "false" otherwise
  mapping (address => bool) public availableForConversion;

  // Checks if address is authorized
  modifier onlyAuthorized() {
    require(Main(mainContractAddress).authorizedAddresses(msg.sender));
    _;
  }

  /**
   *  Constructor function.
   *  Sets necessary addresses.
   */
  function Forex(address _mainContractAddress, address _doto, address _euto, address _krto, address _yuto, address _yeto) public {
    mainContractAddress = _mainContractAddress;
    dotoAddress = _doto;
    eutoAddress = _euto;
    krtoAddress = _krto;
    yutoAddress = _yuto;
    yetoAddress = _yeto;
  }

  // Make specific stable token available for conversion
  function makeAvailable(address _stableToken) public onlyAuthorized {
    availableForConversion[_stableToken] = true;
  }

  // Make specific stable token unavailable for conversion
  function makeUnavailable(address _stableToken) public onlyAuthorized {
    availableForConversion[_stableToken] = false;
  }

  /**
   *  Change one stable token for other at current price.
   *  Burns sent tokens and mints other ones.
   */
  function exchange(address _firstCurrency, address _secondCurrency, uint256 _amount) public {
    // Both specified tokens must be "stable ones"
    require(_firstCurrency == dotoAddress || _firstCurrency == eutoAddress || _firstCurrency == krtoAddress || _firstCurrency == yutoAddress || _firstCurrency == yetoAddress);
    require(_secondCurrency == dotoAddress || _secondCurrency == eutoAddress || _secondCurrency == krtoAddress || _secondCurrency == yutoAddress || _secondCurrency == yetoAddress);
    // Both stable token must be available for conversion
    require(availableForConversion[_firstCurrency]);
    require(availableForConversion[_secondCurrency]);
    // Calculates fee
    uint256 fee = (2 * _amount) / 1000;
    // Burns the amount sent
    require(StableToken(_firstCurrency).burnFrom(msg.sender, _amount - fee));
    require(StableToken(_firstCurrency).transferFrom(msg.sender, this, fee));

    // Takes prices from StableToken contracts, for each token
    uint256 firstPrice = StableToken(_firstCurrency).currentPriceInEth();
    uint256 secondPrice = StableToken(_secondCurrency).currentPriceInEth();
    // Calculates the amount to mint
    uint256 toSend = ((_amount - fee) * firstPrice) / secondPrice;
    // Mints stable tokens
    StableToken(_secondCurrency).mint(toSend, msg.sender);
    fees[_firstCurrency] += fee;
  }

  // Withdraws fee from the contract
  // Only authorized addresses can call this function
  function withdrawFee(address _currency) public onlyAuthorized {
    uint256 toSend = fees[_currency];
    fees[_currency] = 0;
    StableToken(_currency).transfer(msg.sender, toSend);
  }

}
