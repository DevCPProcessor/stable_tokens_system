pragma solidity ^0.4.16;

contract ERC20Interface {
    function burnFrom(address _from, uint256 _value) public returns (bool);
    function transfer(address _to, uint256 _value) public;
    function balanceOf(address _of) public returns (uint256);
    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool);
}
