pragma solidity ^0.4.16;

contract Main {

  // Timestamp of the moment until all the processes are paused
  uint256 public pausedUntil;
  // Minimum amount of cPRO tokens one must have to call certain functions
  uint256 public minCProAmount;
  // Portion of fee inside PersonalConversion.sol that goes to oracle
  uint256 public oraclePercent;

  // Oracle account address
  address public oracleAddress;
  // cPRO Buyback contract address
  address public buybackContractAddress;
  // cPRO token address
  address public cProTokenAddress;

  // Stable tokens' addresses
  address public dotoAddress;
  address public eutoAddress;
  address public krtoAddress;
  address public yetoAddress;
  address public yutoAddress;

  // Derivative addresses
  address public doesAddress;
  address public upesAddress;

  // Tracks whether specific stable token is activated for conversion
  mapping (address => bool) public activatedStabileTokens;

  // SuperAdmin addresses can regulate privileges for other addresses
  mapping (address => bool) public superAdminAddresses;
  // Authorized addresses can call functions like "withdrawEthFee" etc
  mapping (address => bool) public authorizedAddresses;
  // "Mint authorized" addresses can call `mint` function inside each of
  // stable tokens, and derivative tokens
  mapping (address => bool) public mintAuthorizedAddresses;

  /**
   *  Constructor function.
   *  Sets superAdmin addresses, which cannot ever change.
   */
  function Main(address[] _superAdmins) public {
    for (uint i = 0; i < _superAdmins.length; i++) {
      superAdminAddresses[_superAdmins[i]] = true;
    }
  }

  // Checks if msg.sender is superAdmin
  modifier onlySuperAdmin() {
    require(superAdminAddresses[msg.sender]);
    _;
  }

  // Checks if msg.sender is authorized
  modifier onlyAuthorized() {
    require(authorizedAddresses[msg.sender]);
    _;
  }

  // Checks if msg.sender is "mint authorized"
  modifier onlyMintAuthorized() {
    require(mintAuthorizedAddresses[msg.sender]);
    _;
  }

  // Authorizes specified address
  // Only superAdmin can call this function
  function authorize(address _address) public onlySuperAdmin {
    authorizedAddresses[_address] = true;
  }

  // Removes privleges from specific address
  // Only superAdmin can call this function
  function unauthorize(address _address) public onlySuperAdmin {
    authorizedAddresses[_address] = false;
  }

  // Gives "mint authorization" to specified address
  // Only superAdmin can call this function
  function mintAuthorize(address _address) public onlySuperAdmin {
    mintAuthorizedAddresses[_address] = true;
  }

  // Removes "mint privileges" from specified address
  // Only superAdmin can call this function
  function mintUnauthorize(address _address) public onlySuperAdmin {
    mintAuthorizedAddresses[_address] = false;
  }

  // Sets pause to the whole system
  function setPause(uint256 _seconds) public onlyMintAuthorized {
    pausedUntil = now + _seconds;
  }

  // Sets oracle address
  function setOracleAddress(address _oracleAddress) public onlySuperAdmin {
    oracleAddress = _oracleAddress;
  }

  // Sets cPRO buyback contract address
  function setBuybackContractAddress(address _buybackContractADdress) public onlySuperAdmin {
    buybackContractAddress = _buybackContractADdress;
  }

  // Sets the portion of ETH fee inside PersonalConversion.sol that is supposed to go to oracle account
  // Only authorized addresses can call this function
  function setOraclePercent(uint256 _oraclePercent) public onlyAuthorized {
    oraclePercent = _oraclePercent;
  }

  // Sets the address of cPRO token
  function setCProTokenAddress(address _cProTokenAddress) public onlySuperAdmin {
    cProTokenAddress = _cProTokenAddress;
  }

  // Sets the minimum amount of cPRO tokens one must have to call certain functions
  function setMinCProAmount(uint256 _minCProAmount) public onlySuperAdmin {
    minCProAmount = _minCProAmount;
  }

  // Functions that set addresses of stable tokens
  function setDoToAddress(address _dotoAddress) public onlySuperAdmin {
    dotoAddress = _dotoAddress;
  }
  function setEuToAddress(address _eutoAddress) public onlySuperAdmin {
    eutoAddress = _eutoAddress;
  }
  function setKrToAddress(address _krtoAddress) public onlySuperAdmin {
    krtoAddress = _krtoAddress;
  }
  function setYeToAddress(address _yetoAddress) public onlySuperAdmin {
    yetoAddress = _yetoAddress;
  }
  function setYuToAddress(address _yutoAddress) public onlySuperAdmin {
    yutoAddress = _yutoAddress;
  }

  // Functions that set addresses of derivative tokens
  function setDoESAddress(address _doesAddress) public onlySuperAdmin {
    doesAddress = _doesAddress;
  }
  function setUpESAddress(address _upesAddress) public onlySuperAdmin {
    upesAddress = _upesAddress;
  }

  // Function that activates specific stable token for conversion
  function activateStableToken(address _stableAddress) public onlySuperAdmin {
    activatedStabileTokens[_stableAddress] = true;
  }

  // Function that makes specific token unavailable for conversion
  function deactivateStableToken(address _stableAddress) public onlySuperAdmin {
    activatedStabileTokens[_stableAddress] = false;
  }

}
