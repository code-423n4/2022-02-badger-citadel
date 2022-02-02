def test_token(MockERC20, deployer, rando):
    decimals = 8
    token = MockERC20.deploy("Test Token", "TEST", decimals, {"from": deployer})

    assert token.decimals() == decimals

    # Mint 10 tokens to buyer
    amount = 10 * 10 ** decimals
    token.mint(amount, {"from": rando})

    assert token.balanceOf(rando) == amount
