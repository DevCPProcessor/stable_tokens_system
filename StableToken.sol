pragma solidity ^0.4.16;

import "./Main.sol";

interface tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public; }

contract StableToken {

  // Main contract address
  address public mainContractAddress;

  // Token public variables
  string public name;
  string public symbol;
  uint256 public decimals = 2;
  uint256 public totalSupply;

  // Price of the smallest stable token unit ("cent", e.g. 10^-2 cUSD) in WEI
  uint256 public currentPriceInEth;
  // Price of the smallest stable token unit ("cent", e.g. 10^-2 cUSD) in smallest units of other token
  mapping (address => uint256) public currentPriceInToken;
  // Price of the smallest stable token unit ("cent", e.g. 10^-2 cUSD) in smallest units of DoES token
  uint256 public currentPriceInDoES;
  // Price of the smallest stable token unit ("cent", e.g. 10^-2 cUSD) in smallest units of UpES token
  uint256 public currentPriceInUpES;

  // This creates a mapping of all balances
  mapping (address => uint256) public balanceOf;
  // This creates a mapping of allowances
  mapping (address => mapping (address => uint256)) public allowance;
  // Generates a public event on the blockchain that will notify clients
  event Transfer(address indexed from, address indexed to, uint256 value);
  // Notifies clients about the amount burnt
  event Burn(address indexed from, uint256 value);


  // Modifier that checks if msg.sender is "superAdmin"
  // It gets this information by reading Main.sol contract
  modifier onlySuperAdmin() {
    require(Main(mainContractAddress).superAdminAddresses(msg.sender));
    _;
  }

  // Modifier that checks if msg.sender is authorized for certain actions
  // It gets this information by reading Main.sol contract
  modifier onlyAuthorized() {
    require(Main(mainContractAddress).authorizedAddresses(msg.sender));
    _;
  }

  // Modifier that checks if msg.sender is "mint authorized"
  // It gets this information by reading Main.sol contract
  modifier onlyMintAuthorized() {
    require(Main(mainContractAddress).mintAuthorizedAddresses(msg.sender));
    _;
  }

  /**
   * Constructor function
   * Initializes contract with custom parameters
   */
  function StableToken(
    // Main.sol contract must be deployed before this one
    address _mainContractAddress,
    string _tokenName,
    string _tokenSymbol
  ) public {
    mainContractAddress = _mainContractAddress;
    name = _tokenName;
    symbol = _tokenSymbol;
  }

  /**
   * Internal transfer, only can be called by this contract
   */
  function _transfer(address _from, address _to, uint256 _value) internal {
      // Prevent transfer to 0x0 address. Use burn() instead
      require(_to != 0x0);
      // Check if the sender has enough
      require(balanceOf[_from] >= _value);
      // Check for overflows
      require(balanceOf[_to] + _value > balanceOf[_to]);
      // Save this for an assertion in the future
      uint previousBalances = balanceOf[_from] + balanceOf[_to];
      // Subtract from the sender
      balanceOf[_from] -= _value;
      // Add the value to the recipient
      balanceOf[_to] += _value;
      Transfer(_from, _to, _value);
      // Asserts are used to use static analysis to find bugs in your code. They should never fail
      assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
  }

  /**
   * Transfer tokens
   *
   * Send `_value` tokens to `_to` from your account
   *
   * @param _to The address of the recipient
   * @param _value the amount to send
   */
  function transfer(address _to, uint256 _value) public {
      _transfer(msg.sender, _to, _value);
  }

  /**
   * Transfer tokens from other address
   *
   * Send `_value` tokens to `_to` in behalf of `_from`
   *
   * @param _from The address of the sender
   * @param _to The address of the recipient
   * @param _value the amount to send
   */
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
      require(_value <= allowance[_from][msg.sender]);     // Check allowance
      allowance[_from][msg.sender] -= _value;
      _transfer(_from, _to, _value);
      return true;
  }

  /**
   * Set allowance for other address
   *
   * Allows `_spender` to spend no more than `_value` tokens in your behalf
   *
   * @param _spender The address authorized to spend
   * @param _value the max amount they can spend
   */
  function approve(address _spender, uint256 _value) public returns (bool success) {
      allowance[msg.sender][_spender] = _value;
      return true;
  }

  /**
   * Set allowance for other address and notify
   *
   * Allows `_spender` to spend no more than `_value` tokens in your behalf, and then ping the contract about it
   *
   * @param _spender The address authorized to spend
   * @param _value the max amount they can spend
   * @param _extraData some extra information to send to the approved contract
   */
  function approveAndCall(address _spender, uint256 _value, bytes _extraData) public returns (bool success) {
      tokenRecipient spender = tokenRecipient(_spender);
      if (approve(_spender, _value)) {
          spender.receiveApproval(msg.sender, _value, this, _extraData);
          return true;
      }
  }

  /**
   * Destroy stable tokens
   *
   * Remove `_value` tokens from the system irreversibly
   *
   * @param _value the amount of stable tokens to burn
   */
  function burn(uint256 _value) public returns (bool success) {
      // Check if the sender has enough stable tokens
      require(balanceOf[msg.sender] >= _value);
      // Subtract from the sender
      balanceOf[msg.sender] -= _value;
      // Updates totalSupply
      totalSupply -= _value;
      Burn(msg.sender, _value);
      return true;
  }

  /**
   * Destroy stable tokens from other account
   *
   * Remove `_value` tokens from the system irreversibly on behalf of `_from`.
   *
   * @param _from the address of the sender
   * @param _value the amount of stable tokens to burn
   */
  function burnFrom(address _from, uint256 _value) public returns (bool success) {
      // Check if the targeted balance is enough
      require(balanceOf[_from] >= _value);
      // Check allowance
      require(_value <= allowance[_from][msg.sender]);
      // Subtract from the targeted balance
      balanceOf[_from] -= _value;
      // Subtract from the sender's allowance
      allowance[_from][msg.sender] -= _value;
      // Update totalSupply
      totalSupply -= _value;
      Burn(_from, _value);
      return true;
  }

  /**
   * Change current stable token price in ether.
   * Can only be called by authorized addresses.
   *
   * @param _newPrice Price at which users can buy from the contract.
   */
  function setPriceInEth(uint256 _newPrice) public onlyAuthorized {
    require(_newPrice > 0);
    if (currentPriceInEth == 0) {
      currentPriceInEth = _newPrice;
      currentPriceInDoES = _newPrice;
      currentPriceInUpES = _newPrice;
    }
    // Pauses everything if price changes more than 5%
    else {
      // Sets pause if current price differs from the last one for more than 5%
      if ((_newPrice > (105 * currentPriceInEth) / 100) || (_newPrice < (95 * currentPriceInEth) / 100)) {
        Main(mainContractAddress).setPause(3600);
      }
      uint256 lastPrice = currentPriceInEth;
      currentPriceInEth = _newPrice;
      // Sets derivative prices
      currentPriceInDoES = (currentPriceInDoES * lastPrice) / _newPrice;
      if (2 * lastPrice <= _newPrice) {
        currentPriceInUpES = 100;
      }
      else {
        currentPriceInUpES = (currentPriceInUpES * _newPrice) / (2 * lastPrice - _newPrice);
      }
    }
  }

  /**
   * Change current stable token price in token.
   * Can only be called by authorized addresses.
   *
   * @param _newPrice Price at which users can buy from the contract.
   */
  function setPriceInToken(address _tokenAddress, uint256 _newPrice) public onlyAuthorized {
    if (currentPriceInToken[_tokenAddress] == 0) {
      currentPriceInToken[_tokenAddress] = _newPrice;
    }
    // Pauses everything if price changes more than 5%
    else {
      if ((_newPrice > (105 * currentPriceInToken[_tokenAddress]) / 100) || (_newPrice < (95 * currentPriceInToken[_tokenAddress]) / 100)) {
        Main(mainContractAddress).setPause(3600);
      }
      currentPriceInToken[_tokenAddress] = _newPrice;
    }
  }

  /**
   *  Mint stable tokens.
   *  Can only be called by "mint authorized" addresses.
   */
  function mint(uint256 _amount, address _to) public onlyMintAuthorized {
    balanceOf[_to] += _amount;
    totalSupply += _amount;
  }

  // Sets prices to defined values, and can be called only by superAdmin
  function reset(uint256 _currentPriceInEth, uint256 _currentPriceInDoES, uint256 _currentPriceInUpES) public onlySuperAdmin {
    currentPriceInEth = _currentPriceInEth;
    currentPriceInDoES = _currentPriceInDoES;
    currentPriceInUpES = _currentPriceInUpES;
  }

}
