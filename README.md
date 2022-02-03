# Badger Citadel contest details
- $28,500 USDC main award pot
- $1,500 USDC gas optimization award pot
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2022-02-badger-citadel-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts February 4, 2022 00:00 UTC
- Ends February 6, 2022 23:59 UTC

# Intro
The Citadel DAO is a black hole for Bitcoin in DeFi and the biggest user of BadgerDAOs products. Its goal is to acquire BTC and other assets that will support its mission of growing the largest BTC focused treasury in DeFi. Initial bootstrap of its treasury will be through a token sale program whose contract is in this audit contest.

The goal of this contest is to determine if the token sale contract is:

- Safe to use
- Mathematically will provide the correct amount of tokens given the inputs

Specific care should be put in:

- Economic exploits
- Rug Vectors

# Contract Description:

[TokenSaleUpgradeable.sol](https://github.com/code-423n4/2022-02-badger-citadel/blob/main/contracts/TokenSaleUpgradeable.sol) - Allows a whitelisted user to deposit a `tokenIn` and after the claiming period begins claim Citadel Tokens.

## Installation
```bash
git submodule update --init --recursive
pip install -r requirements.txt
yarn install
curl -L https://foundry.paradigm.xyz | bash
```

## Test
```bash
brownie test
forge test
```
