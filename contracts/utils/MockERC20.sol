// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private decimalsVar;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        decimalsVar = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return decimalsVar;
    }

    function mint(uint256 _amount) external {
        _mint(msg.sender, _amount);
    }
}
