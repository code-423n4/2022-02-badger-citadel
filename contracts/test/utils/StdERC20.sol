// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "./StdStorageInMemory.sol";

import "openzeppelin-contracts/token/ERC20/ERC20.sol";

library StdERC20 {
    using stdStorageInMemory for StdStorageInMemory;

    // event Transfer(address indexed from, address indexed to, uint256 value);

    function forceMintTo(
        ERC20 token,
        address account,
        uint256 amount
    ) internal {
        StdStorageInMemory memory stdstore;

        stdstore
            .target(address(token))
            .sig(token.balanceOf.selector)
            .with_keys(abi.encode(account))
            .checked_write(amount);

        stdstore
            .target(address(token))
            .sig(token.totalSupply.selector)
            .checked_write(token.totalSupply() + amount);

        // Should be emitted by token contract
        // emit Transfer(address(0), account, amount);
    }

    function forceMint(ERC20 token, uint256 amount) internal {
        forceMintTo(token, address(this), amount);
    }

    function forceBurnFrom(
        ERC20 token,
        address account,
        uint256 amount
    ) internal {
        StdStorageInMemory memory stdstore;

        stdstore
            .target(address(token))
            .sig(token.balanceOf.selector)
            .with_keys(abi.encode(account))
            .checked_write(token.balanceOf(account) - amount);

        stdstore
            .target(address(token))
            .sig(token.totalSupply.selector)
            .checked_write(token.totalSupply() - amount);

        // Should be emitted by token contract
        // emit ERC20.Transfer(account, address(0), amount);
    }

    function forceBurn(ERC20 token, uint256 amount) internal {
        forceBurnFrom(token, address(this), amount);
    }
}

// TODO:
// - events?
