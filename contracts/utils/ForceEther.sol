// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

/*
    Send ETH to any account, including contracts that do not accept it.
    Useful when --unlocking contract accounts via Ganache
*/
contract ForceEther {
    function forceSend(address payable recipient) external {
        selfdestruct(recipient);
    }

    receive() external payable {}
}
