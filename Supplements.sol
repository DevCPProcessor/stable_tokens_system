pragma solidity ^0.4.16;

import "./Main.sol";
import "./StableToken.sol";

contract Supplements {

  // Main contract address
  address public mainContractAddress;

  // Total amount of eth stored as collateral
  uint256 public totalConvertEth;
  // Total amount of specific tokens stored as collateral
  mapping (address => uint256) public totalConvertTokens;
  // Mapps token address to "true" if token is listed, to "false" otherwise
  mapping (address => bool) public listed;

  // Total amount of stable tokens stored as collateral
  mapping (address => uint256) public totalConvertCollateral;

  // Addresses of stable tokens
  address[] public stableTokens;
  // Addresses of listed tokens
  address[] public listedTokens;

  // Checks if msg.sender is "mint authorized"
  modifier onlyMintAuthorized() {
    require(Main(mainContractAddress).mintAuthorizedAddresses(msg.sender));
    _;
  }

  // Checks if msg.sender is superAdmin
  modifier onlySuperAdmin() {
    require(Main(mainContractAddress).superAdminAddresses(msg.sender));
    _;
  }

  /*
   *  Constructor function.
   *  Sets main contract address and the list of stable tokens.
   */
  function Supplements(address _mainContractAddress, address[] _stableTokens) public {
    mainContractAddress = _mainContractAddress;
    stableTokens = _stableTokens;
  }

  // Function that should be used if the number of stable tokens changes
  // Sets the new list of stable tokens
  function setStableTokens(address[] _stableTokens) public onlySuperAdmin {
    stableTokens = _stableTokens;
  }

  // Increases total amount of collateral eth
  function increaseTotalConvertEth(uint256 _amount) public onlyMintAuthorized {
    totalConvertEth += _amount;
  }

  // Decreases total amount of collateral eth
  function decreseTotalConvertEth(uint256 _amount) public onlyMintAuthorized {
    require(totalConvertEth >= _amount);
    totalConvertEth -= _amount;
  }

  // Increases total amount of specific tokens stored as collateral
  function increaseTotalConvertTokens(uint256 _amount, address _tokenAddress) public onlyMintAuthorized {
    totalConvertTokens[_tokenAddress] += _amount;
  }

  // Decreases total amount of specific tokens stored as collateral
  function decreseTotalConvertTokens(uint256 _amount, address _tokenAddress) public onlyMintAuthorized {
    require(totalConvertTokens[_tokenAddress] >= _amount);
    totalConvertTokens[_tokenAddress] -= _amount;
  }

  // Increases total amount of collateral stables
  function increaseTotalConvertCollateral(uint256 _amount, address _stableAddress) public onlyMintAuthorized {
    totalConvertCollateral[_stableAddress] += _amount;
  }

  // Decreases total amount of collateral stables
  function decreseTotalConvertCollateral(uint256 _amount, address _stableAddress) public onlyMintAuthorized {
    require(totalConvertCollateral[_stableAddress] >= _amount);
    totalConvertCollateral[_stableAddress] -= _amount;
  }

  // Sets listed tokens
  function setListedTokens(address[] _listedTokens) public onlySuperAdmin {
    listedTokens = _listedTokens;
  }

  // Calculates global supplements and returns it in terms of stable tokens related to specified address
  function supplementsInStables(address _stableAddress) constant returns (uint256) {
    uint256 totalCollateralValueInStables;
    for (uint i = 0; i < listedTokens.length; i++) {
      uint256 price = StableToken(_stableAddress).currentPriceInToken(listedTokens[i]);
      require(price > 0);
      totalCollateralValueInStables += totalConvertTokens[listedTokens[i]] / price;
    }
    totalCollateralValueInStables += totalConvertEth / StableToken(_stableAddress).currentPriceInEth();

    uint256 stablePriceInEth = StableToken(_stableAddress).currentPriceInEth();
    uint256 stablesCollateralValueInStables;
    uint256 totalSupplyValue;

    for (i = 0; i < stableTokens.length; i++) {
      stablesCollateralValueInStables += (totalConvertCollateral[stableTokens[i]] * StableToken(stableTokens[i]).currentPriceInEth()) / StableToken(_stableAddress).currentPriceInEth();
      totalSupplyValue += (StableToken(stableTokens[i]).totalSupply() * StableToken(stableTokens[i]).currentPriceInEth()) / StableToken(_stableAddress).currentPriceInEth();
    }

    if (totalSupplyValue - stablesCollateralValueInStables <= totalCollateralValueInStables) {
      return 0;
    }
    else {
      return (totalSupplyValue - stablesCollateralValueInStables - totalCollateralValueInStables);
    }
  }

  function totalStablesSupplyInStable(address _stableAddress) constant returns (uint256) {
    uint256 totalSupplyValue;
    for (uint i = 0; i < stableTokens.length; i++) {
      totalSupplyValue += (StableToken(stableTokens[i]).totalSupply() * StableToken(stableTokens[i]).currentPriceInEth()) / StableToken(_stableAddress).currentPriceInEth();
    }
    return totalSupplyValue;
  }

  function totalConvertEthInStable(address _stableAddress) constant returns (uint256) {
    return (totalConvertEth / StableToken(_stableAddress).currentPriceInEth());
  }

  function totalConvertTokensInStable(address _stableAddress) constant returns (uint256) {
    uint256 totalConvertTokensValue;
    for (uint i = 0; i < listedTokens.length; i++) {
      uint256 price = StableToken(_stableAddress).currentPriceInToken(listedTokens[i]);
      require(price > 0);
      totalConvertTokensValue += totalConvertTokens[listedTokens[i]] / price;
    }
    return totalConvertTokensValue;
  }


}
