pragma solidity ^0.4.16;

import "./StandardToken.sol";
import "./StableToken.sol";
import "./Main.sol";
import "./Supplements.sol";

contract Discount {

  // Main.sol convtract address
  address public mainContractAddress;
  // Specific stable token address
  address public stableTokenAddress;
  // Supplements.sol contract address
  address public supplementsContractAddress;
  // Specific discount token address
  address public didoTokenAddress;


  /**
   *  Constructor function.
   *  Sets addresses of Main.sol, specific stable token,
   *  Supplements.sol and specific discount token.
   */
  function Discount(
    address _mainContractAddress,
    address _stableTokenAddress,
    address _supplementsContractAddress,
    address _didoTokenAddress
  ) public {
    mainContractAddress = _mainContractAddress;
    stableTokenAddress = _stableTokenAddress;
    supplementsContractAddress = _supplementsContractAddress;
    didoTokenAddress = _didoTokenAddress;
  }


  /**
   *  Converts stable tokens to discount tokens.
   *  One will get 1.03 x _amount of discount tokens, where _amount is
   *  the amount of stable tokens sent.
   */
  function buy(uint256 _amount) public {
    // Reads from Supplements.sol contract for call requirements
    uint256 totalSupply = Supplements(supplementsContractAddress).totalStablesSupplyInStable(stableTokenAddress);
    uint256 totalEth = Supplements(supplementsContractAddress).totalConvertEthInStable(stableTokenAddress);
    uint256 totalTokens = Supplements(supplementsContractAddress).totalConvertTokensInStable(stableTokenAddress);
    uint256 totalConvertStables = Supplements(supplementsContractAddress).totalStableConvert(stableTokenAddress);

    // Checks the "mint" condition
    require(totalSupply >= 45 * (totalEth + totalTokens + totalConvertStables) / 100);
    // Burns stable tokens sent
    require(StableToken(stableTokenAddress).burnFrom(msg.sender, _amount));

    uint256 toMint = (103 * _amount) / 100;

    // Updates Supplements.sol contract
    Supplements(supplementsContractAddress).increaseTotalStableConvert(toMint - _amount, stableTokenAddress);
    // Mints discount tokens
    StandardToken(didoTokenAddress).mint(toMint, msg.sender);
  }

  /**
   *  Converts discount tokens to stable tokens.
   *  One will get _amount of stable tokens, where _amount is
   *  the amount of discount tokens sent.
   */
  function sell(uint256 _amount) public {
    // Reads from Supplements.sol contract for call requirements
    uint256 totalSupply = Supplements(supplementsContractAddress).totalStablesSupplyInStable(stableTokenAddress);
    uint256 totalEth = Supplements(supplementsContractAddress).totalConvertEthInStable(stableTokenAddress);
    uint256 totalTokens = Supplements(supplementsContractAddress).totalConvertTokensInStable(stableTokenAddress);
    uint256 totalConvertStables = Supplements(supplementsContractAddress).totalStableConvert(stableTokenAddress);

    // Checks the "burn" condition
    require((totalSupply * 23) / 10 <= (totalEth + totalTokens + totalConvertStables));
    // Burns discount tokens sent
    require(StandardToken(didoTokenAddress).burnFrom(msg.sender, _amount));

    // Updates Supplements.sol contract
    uint256 toReduce = (3 * _amount) / 103;
    Supplements(supplementsContractAddress).decreaseTotalStableConvert(toReduce, stableTokenAddress);
    // Mints stable tokens
    StableToken(stableTokenAddress).mint(_amount, msg.sender);
  }

}
