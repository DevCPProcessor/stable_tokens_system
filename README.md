# README v0.1 / 2018.03.19.

# ETHEREUM STABLE TOKENS SYSTEM 

# Introduction
StableToken.sol is the contract that generates stable tokens through its function `mint`.  
That function can be triggered only by "mintAuthorized" contracts (addresses), when they receive ETH or other listed ERC20 tokens.  
Calculation of the amount of stable tokens that should be generated is based on the price of stable token in Eth or in other tokens which is provided by a centralized oracle service.  

Stable tokens can be bought in two ways:  
1. By sending ETH to PersonalEthConversion.sol contract, which calls `mint` function from StableToken.sol that sends the equivalent amount of stable tokens to sender's address.  
2. By sending (listed) ERC20 tokens to specific token's PersonalTokenConversion.sol contract that works the same as PersonalEthConversion.sol, but only with specific listed token.  

DoES and UpES tokens can be bought through each of PersonalEthConversion.sol or PersonalTokenConversion.sol contracts. Their price is updated within StableToken.sol contract each time
ETH price is updated.  

StandardToken.sol is the contract that generates DoES or UpES tokens. It should be deployed twice for each token.  

DoES will only be available for purchase if its capitalization is lower than 105% of UpES capitalization, and vice versa:  
```
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
```


DoES tokens act as "short ETH" tokens. Its price (expressed in specific stable token) goes up if ETH goes down, and vice versa:  
```
      uint256 lastPrice = currentPriceInEth;
      currentPriceInEth = _newPrice;
      currentPriceInDoES = (currentPriceInDoES * lastPrice) / _newPrice;
```  

UpES tokens act as "2x long ETH" tokens. Its price (expressed in specific stable token) goes up/down two times faster than the price of ETH:  
```
      currentPriceInUpES = (currentPriceInUpES * _newPrice) / (2 * lastPrice - _newPrice);
```

Main.sol contract is the contract for system administration. It regulates privileges for all contracts and adresses, and most of its functions can be called only by "superAdmin". `SuperAdminAddresses` are defined during deployment.  
SuperAdmins are such addresses that give both "mint" and "standard" authorization. `mintAuthorizedAddresses` are able to call StableToken.sol's and StandardToken.sol's `mint` function:  
```
  /**
   *  Mint stable tokens.
   *  Can only be called by "mint authorized" addresses.
   */
  function mint(uint256 _amount, address _to) public onlyMintAuthorized {
    balanceOf[_to] += _amount;
    totalSupply += _amount;
  }
```

While `authorizedAddresses` are able to call functions like `withdrawEthFee`, `withdrawStablesFee` (PersonalEthConversion.sol), `withdrawTokenFee` (PersonalTokenConversion.sol), `setPriceInEth`, `setPriceInToken` (StableToken.sol),
`makeAvailable`, `makeUnavailable`, `withdrawFee` (Forex.sol), `setOraclePercent` (Main.sol).

Supplements.sol is the contract that tracks the summ of all converts, in order to provide PersonalEthConversion.sol and PersonalTokenConversion.sol contracts with the amount of excess stable tokens.  
```
  function supplementsInStables(address _stableAddress) constant returns (uint256) { ... }
```

## Table of Contents (TOC)
1. Usage
2. Requirements and Installation
3. Deployment
4. Running the tests

# Usage (getting started)

To generate stable tokens one must send ETH to PersonalEthConversion.sol contract (which activates fallback function):  
```
  // Fallback function
  function () public payable {
    buy();
  }

  /**
   *  Exchange Eth for stable tokens at current price.
   *  Sent Eth is stored as convert, and stable tokens are minted to msg.sender.
   */
  function buy() public payable isNotPaused {...}
```  
This creates or updates msg.sender's convert that tracks how much Eth msg.sender has sent. It also remembers the amount of stable tokens that are minted for msg.sender:  
```
  /**
   *  State of specific convert.
   */
  struct EthConvert {
    // Amount of stable tokens minted by sending Eth
    uint256 stable;
    // Amount of Eth sent
    uint256 convertEth;
  }
```

Other way to generate stable tokens is by sending tokens to PersonalTokenConversion.sol contract for specific token. It works the same as PersonalEthConversion.sol, but with tokens instead of Eth,
hence, there is not fallback function. First, PersonalTokenConversion.sol must have the sender's approval to transfer tokens from him to itself (ERC20 standard), so msg.sender must first interact with
token contract in order to give approval (by calling `approve` ERC20 function). After that, `buy` function inside PersonalTokenConversion.sol may be called:  
```
  /**
   *  Exchange Eth for stable tokens at current price.
   *  Sent Eth is stored as convert, and stable tokens are minted to msg.sender.
   */
  function buy(uint256 _amount) public isNotPaused activatedStable {...}
```


One may repurchase ETH with stable tokens he generated, at current price (provided by oracle). If the value of stored ETH and other listed tokens is lower than the value of stable tokens initally generated from that
amount of ETH and tokens, or the total value of convert ETH and tokens is lower than the value of circulating stable tokens ("global supplements"), one may choose to buy DoES or UpES tokens for non-convertalized
amount of stable tokens (or for any amount of stable tokens in case of "global supplements") by calling `buyDoES` or `buyUpES` function withing PersonalEthConversion.sol or PersonalTokenConversion.sol contract:  
```
  function buyDoES(uint256 _stablesAmount, address _tokenAddress) public checkForDoES isNotPaused {...}
  function buyUpES(uint256 _stablesAmount, address _tokenAddress) public checkForUpES isNotPaused {...}
```  

Also, total capitalization of DoES token will be in balance with capitalization of UpES token, as only DoES tokens will be available for purchase if its capitalization is more than 5% lower than UpES capitalization
and vice versa:  
```
  // Checks if DoES is available for purchase
  modifier checkForDoES() {
    // Calculates capitalization of both DoES and UpES in order to compare them
    uint256 doesCap = StandardToken(doesTokenAddress).totalSupply() * StableToken(stableTokenAddress).currentPriceInDoES();
    uint256 upesCap = StandardToken(upesTokenAddress).totalSupply() * StableToken(stableTokenAddress).currentPriceInUpES();
    require(doesCap <= (105 * upesCap) / 100);
    _;
  }

  // Checks if UpES is available for purchase
  modifier checkForUpES() {
    // Calculates capitalization of both DoES and UpES in order to compare them
    uint256 doesCap = StandardToken(doesTokenAddress).totalSupply() * StableToken(stableTokenAddress).currentPriceInDoES();
    uint256 upesCap = StandardToken(upesTokenAddress).totalSupply() * StableToken(stableTokenAddress).currentPriceInUpES();
    require(upesCap <= (105 * doesCap) / 100);
    _;
  }
```  
The same goes for PersonalTokenConversion.sol contract:  
```
  function buybackTokens(uint256 _stablesAmount, address _tokenAddress) public isNotPaused cProRequirement {...}
```

# Requirements (prerequest) and Installation
The contracts themselves do not have any requirements and no additional software should be installed.  
On the other hand, an oracle that provides the contract StableToken.sol with price implements web3 library (https://web3js.readthedocs.io/en/latest/), but that is not part of this repository.


# Deployment
In order to deploy all contracts, one must have enough ETH to pay for the gas.  
Main.sol contract must be deployed first, as constructors of other contracts take its address as parameter.  
Constructor parameters for Main.sol are:  
1. address[] _superAdmins - the list of addresses that will be able to give `mint` and `standard` privileges to other addresses and contracts  

```
  function Main(address[] _superAdmins) public {
    for (uint i = 0; i < _superAdmins.length; i++) {
      superAdminAddresses[_superAdmins[i]] = true;
    }
  }
```

For each fiat currency (USD, EUR, KRW, JPY, CNY), StableToken.sol contract must be deployed (e.g. it must be deployed 5 times).  
Constructor parameters are:  
1. _mainContractAddress - address of the Main.sol contract  
2. _tokenName - official name of stable token (e.g. "Dollar Token", "Euro Token", etc)  
3. _tokenSymbol - official symbol of stable token (e.g. "DoTo", "EuTo", etc)  

After 5 deployments of StableToken.sol, superAdmin address must call `mintAuthorize` function within Main.sol contract in order to give `mint authorization` to each StableToken.sol contract:  
```
  function mintAuthorize(address _address) public onlySuperAdmin {
    mintAuthorizedAddresses[_address] = true;
  }
```

Also, oracle address must be authorized in order to call `setPriceInEth` and `setPriceInToken` functions within StableToken.sol contracts, so superAdmin must give authorization to oracle address
by calling Main.sol's `authorize` function:  
```
  function authorize(address _address) public onlySuperAdmin {
    authorizedAddresses[_address] = true;
  }
```

Other than that, superAdmin address must call `setOracleAddress` and `setBuybackContractAddress` functions, so that fee from PersonalEthConversion.sol could go to both oracle and buyback contract in the future:  
```
  function setOracleAddress(address _oracleAddress) public onlySuperAdmin {
    oracleAddress = _oracleAddress;
  }

  function setBuybackContractAddress(address _buybackContractADdress) public onlySuperAdmin {
    buybackContractAddress = _buybackContractADdress;
  }
```

Authorized addresses ("standard" authorization) may call `setOraclePercent` function within Main.sol in order to specify the portion of fee inside PersonalEthConversion.sol that should go to oracle:  
```
  function setOraclePercent(uint256 _oraclePercent) public onlyAuthorized {
    oraclePercent = _oraclePercent;
  }
```

SuperAdmin should also "activate" each stable token so conversion may be possible, by calling Main.sol's `activateStableToken` function:  
```
  function activateStableToken(address _stableAddress) public onlySuperAdmin {
    activatedStables[_stableAddress] = true;
  }
```



After deployment of StableToken.sol, StandardToken.sol should be deployed twice, as each deployment creates a contract that generates DoES/UpES tokens.  
Constructor parameters are:  
1. _mainContractAddress - address of the Main.sol contract    
2. _name - official token name  
3. _symbol - official token symbol  
4. _initialSupply - initial supply of the token (should be set to 0)

```
    function StandardToken(
        string _name,
        string _symbol,
        uint256 _initialSupply,
        address _stableTokenAddress
    ) public {
        // Update total supply with the decimal amount
        totalSupply = _initialSupply * 10 ** decimals;
        balanceOf[msg.sender] += totalSupply;
        // Set the name for display purposes
        name = _name;
        // Set the symbol for display purposes
        symbol = _symbol;

        stableTokenAddress = _stableTokenAddress;
    }
```  

After deployment of DoES and UpES tokens, superAdmin must call `setDoESAddress` and `setUpESAddress` functions within Main.sol:  
```
  function setDoESAddress(address _doesAddress) public onlySuperAdmin {
    doesAddress = _doesAddress;
  }

  function setUpESAddress(address _upesAddress) public onlySuperAdmin {
    upesAddress = _upesAddress;
  }
```

After DoES and UpES tokens, Supplements.sol should be deployed.  
Constructor parameters are:  
1. address _mainContractAddress - address of the Main.sol contract  
2. address[] _stableTokens - the list of addresses of all stable tokens  


After Supplements.sol, stable tokens and DoES and UpES tokens are all deployed, PersonalEthConversion.sol should be deployed for each stable token token (5 deployments in total).  
Also, PersonalTokenConversion.sol must be deployed 5 times for each listed token (5N deployments).  
Constructor parameters for PersonalEthConversion.sol are:  
1. _mainContractAddress - address of the Main.sol contract  
2. address _supplementsContractAddress - Supplements.sol contract address  
3. address _stableTokenAddress - specific stable token's address  

```
  /**
   *  Constructor function.
   *  Sets all relevant addresses.
   */
  function PersonalEthConversion(
    address _mainContractAddress,
    address _supplementsContractAddress,
    address _stableTokenAddress
  ) public {
    mainContractAddress = _mainContractAddress;
    supplementsContractAddress = _supplementsContractAddress;
    stableTokenAddress = _stableTokenAddress;
  }
```

Constructor parameters for PersonalTokenConversion.sol are:  
1. _mainContractAddress - address of the Main.sol contract  
2. address _supplementsContractAddress - Supplements.sol contract address  
3. address _stableTokenAddress - specific stable token's address  
4. address _tokenAddress - address of specific listed token  

```
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
```

PersonalTokenConversion.sol should also be `mintAuthorized` in order to work properly, so superAdmin should call `mintAuthorize` function with PersonalTokenConversion.sol's address as a parameter.  

At the end, Forex.sol contract should be deployed.  
Constructor parameters for Forex.sol are:  
1. _doto - the address of DoTo contract  
2. _euto - the address of EuTo contract  
3. _krto - the address of KrTo contract  
4. _yuto - the address of YuTo contract  
5. _yeto - the address of YeTo contract  

```
  function Forex(address _doto, address _euto, address _krto, address _yuto, address _yeto) public {
    dotoAddress = _doto;
    eutoAddress = _euto;
    krtoAddress = _krto;
    yutoAddress = _yuto;
    yetoAddress = _yeto;
  }
```

After all these contract are deployed, and authorizations are set, 5 StandardToken.sol's should be deployed, each representing one Discount token for each stable token.  
When discount tokens are deployed, Discount.sol and Interest.sol contracts should be deployed. Authorization should be given to each of these contracts so they could mint
stable tokens (Discount.sol also mints discount tokens).  
Constructor parameters for Discount.sol are:  
1. _mainContractAddress - the address of Main.sol contract  
2. _stableTokenAddress - the address of specific stable token  
3. _supplementsContractAddress - the address of Supplements.sol contract  
4. _dixxTokenAddress - the address of specific DiXX token  

```
function Discount(
  address _mainContractAddress,
  address _stableTokenAddress,
  address _supplementsContractAddress,
  address _didoTokenAddress
) public {
  mainContractAddress = _mainContractAddress;
  stableTokenAddress = _stableTokenAddress;
  supplementsContractAddress = _supplementsContractAddress;
  dixxTokenAddress = _dixxTokenAddress;
}
```

Constructor parameters for Interest.sol are:  
1. _mainContractAddress - the address of Main.sol contract  
2. _stableTokenAddress - the address of specific stable token  
3. _personalEthConversionAddress - the address of PersonalEthConversion.sol contract for specific stable token  

```
function Interest(
  address _mainContractAddress,
  address _stableTokenAddress,
  address _personalEthConversionAddress
) public {
  mainContractAddress = _mainContractAddress;
  stableTokenAddress = _stableTokenAddress;
  personalEthConversionAddress = _personalEthConversionAddress;
}
```

These contracts also must be `mintAuthorized` in order to work.  

After prices are set for the first time by the oracle, the system can start converting between values.

### Running the tests
Testing may be performed on Kovan, or any other testnet.  
The easiest way to test all functions is to deploy contracts to the testnet using some injected web3 (Metamask: https://metamask.io/) through Remix Solidity IDE (https://remix.ethereum.org/). Remix will display all functions after deployment.


### Credits (authors)
GVISP1 TEAM

### Contact
GVISP1 Ltd
web: https://www.gvisp.com
mail: office@gvisp.com

# License
This project is licensed under GPL3, https://www.gnu.org/licenses/gpl-3.0.en.html 
The license should be in a separate file called LICENSE.
