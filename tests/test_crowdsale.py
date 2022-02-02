import brownie
import pytest

from conftest import ADDRESS_ZERO, DURATION, MAX_UINT256


@pytest.fixture()
def crowdsale(
    TokenSaleUpgradeable,
    chain,
    owner,
    ctdl,
    treasury,
    token_in_params,
    buyer,
    rando,
):
    token_sale = TokenSaleUpgradeable.deploy({"from": owner})
    token_in = token_in_params["token"]
    token_sale.initialize(
        ctdl,  # tokenOut
        token_in,
        chain.time() + 10,  # saleStart
        DURATION,
        token_in_params["price"],
        treasury,  # Sale recipient
        ADDRESS_ZERO,
        MAX_UINT256,  # Sale cap in tokenIn
        {"from": owner},
    )
    chain.sleep(10)

    # Approvals
    token_in.approve(token_sale, MAX_UINT256, {"from": buyer})
    token_in.approve(token_sale, MAX_UINT256, {"from": rando})

    yield token_sale


@pytest.fixture()
def get_amount_out(token_in_params, ctdl):
    def helper(amount_in, price=token_in_params["price"]):
        return amount_in * 10 ** ctdl.decimals() // price

    yield helper


def test_initialize_multiple(crowdsale, chain, owner, ctdl, treasury, token_in_params):
    with brownie.reverts("Initializable: contract is already initialized"):
        crowdsale.initialize(
            ctdl,
            token_in_params["token"],
            chain.time(),
            DURATION,
            token_in_params["price"],
            treasury,
            ADDRESS_ZERO,
            MAX_UINT256,
            {"from": owner},
        )


def test_owner(crowdsale, owner):
    assert crowdsale.owner() == owner


def test_transfer_ownership(crowdsale, owner, rando):
    crowdsale.transferOwnership(rando, {"from": owner})

    assert crowdsale.owner() == rando


def test_pause(crowdsale, owner):
    crowdsale.pause({"from": owner})

    assert crowdsale.paused()


def test_unpause(crowdsale, owner):
    crowdsale.pause({"from": owner})
    crowdsale.unpause({"from": owner})

    assert not crowdsale.paused()


# Maybe fuzz
def test_amount_out(crowdsale, token_in, get_amount_out):
    amount_in = 10 ** token_in.decimals()
    amount_out = crowdsale.getAmountOut(amount_in)

    assert amount_out == get_amount_out(amount_in)


@pytest.fixture()
def buy_checked(crowdsale, token_in_params, treasury, get_amount_out):
    token_in = token_in_params["token"]

    def helper(
        amount_in,
        tx_params,
        dao_id=0,
        proof=[],
        price=token_in_params["price"],
        recipient=treasury,
    ):
        caller = tx_params["from"]

        assert amount_in > 0

        # State before tx
        before = {
            "recipeint_bal": token_in.balanceOf(recipient),
            "caller_bal": token_in.balanceOf(caller),
            "boughtAmounts": crowdsale.boughtAmounts(caller),
            "daoCommitments": crowdsale.daoCommitments(dao_id),
            "totalTokenIn": crowdsale.totalTokenIn(),
            "totalTokenOutBought": crowdsale.totalTokenOutBought(),
        }

        # Expected output
        amount_out = get_amount_out(amount_in, price=price)

        tx = crowdsale.buy(amount_in, dao_id, proof, {"from": caller})

        # Verify events
        assert len(tx.events["Sale"]) == 1

        event = tx.events["Sale"][0]
        assert event["buyer"] == caller
        assert event["daoId"] == dao_id
        assert event["amountIn"] == amount_in
        assert event["amountOut"] == amount_out

        # Verify return val
        assert tx.return_value == amount_out

        # Verify state changes
        assert crowdsale.boughtAmounts(caller) == before["boughtAmounts"] + amount_out
        assert crowdsale.daoCommitments(dao_id) == before["daoCommitments"] + amount_out

        assert crowdsale.totalTokenIn() == before["totalTokenIn"] + amount_in
        assert (
            crowdsale.totalTokenOutBought()
            == before["totalTokenOutBought"] + amount_out
        )

        assert crowdsale.daoVotedFor(caller) == dao_id

        # Verify balances
        assert token_in.balanceOf(caller) == before["caller_bal"] - amount_in
        assert token_in.balanceOf(recipient) == before["recipeint_bal"] + amount_in

        return amount_out

    yield helper


@pytest.fixture()
def finalize_checked(crowdsale, ctdl, owner):
    def helper(tx_params, extra_out=0):
        # Mint and transfer required amount to contract
        total_out = crowdsale.totalTokenOutBought() + extra_out
        ctdl.mint(total_out, {"from": owner})
        ctdl.transfer(crowdsale, total_out, {"from": owner})

        caller = tx_params["from"]

        tx = crowdsale.finalize({"from": caller})

        # Verify events
        assert len(tx.events["Finalized"]) == 1

        assert crowdsale.finalized()

    yield helper


@pytest.fixture()
def claim_checked(crowdsale, ctdl):
    def helper(expected_out, tx_params):
        caller = tx_params["from"]

        assert expected_out > 0

        # State before tx
        before = {
            "caller_bal": ctdl.balanceOf(caller),
            "contract_bal": ctdl.balanceOf(crowdsale),
            "totalTokenOutClaimed": crowdsale.totalTokenOutClaimed(),
        }

        tx = crowdsale.claim({"from": caller})

        # Verify events
        assert len(tx.events["Claim"]) == 1

        event = tx.events["Claim"][0]
        assert event["claimer"] == caller
        assert event["amount"] == expected_out

        # Verify return val
        assert tx.return_value == expected_out

        # Verify state changes
        assert crowdsale.hasClaimed(caller)
        assert (
            crowdsale.totalTokenOutClaimed()
            == before["totalTokenOutClaimed"] + expected_out
        )

        # Verify balances
        assert ctdl.balanceOf(caller) == before["caller_bal"] + expected_out
        assert ctdl.balanceOf(crowdsale) == before["contract_bal"] - expected_out

    yield helper


def test_buy_before_start(crowdsale, buyer, token_in, chain):
    crowdsale.setSaleStart(chain.time() + 60)

    # Inputs
    amount_in = 10 ** token_in.decimals()

    with brownie.reverts("TokenSale: not started"):
        crowdsale.buy(amount_in, 0, [], {"from": buyer})


def test_buy(buyer, token_in, buy_checked):
    # Inputs
    amount_in = 10 ** token_in.decimals()

    buy_checked(amount_in, tx_params={"from": buyer})


def test_buy_zero(crowdsale, buyer):
    with brownie.reverts("_tokenInAmount should be > 0"):
        crowdsale.buy(0, 0, [], {"from": buyer})


def test_buy_multiple_buyers(buyer, rando, token_in, buy_checked):
    # Inputs
    amount_in = 10 ** token_in.decimals()

    buy_checked(amount_in, tx_params={"from": buyer})
    buy_checked(amount_in, tx_params={"from": rando})


def test_buy_multiple_buys(buyer, token_in, buy_checked):
    # Inputs
    amount_in = 10 ** token_in.decimals()

    buy_checked(amount_in, tx_params={"from": buyer})
    # Mixing it up with dao_id
    buy_checked(amount_in, tx_params={"from": buyer})


def test_buy_multiple_daos(buyer, token_in, buy_checked, crowdsale):
    # Inputs
    amount_in = 10 ** token_in.decimals()

    buy_checked(amount_in, tx_params={"from": buyer})

    with brownie.reverts("can't vote for multiple daos"):
        crowdsale.buy(amount_in, 1, [], {"from": buyer})


def test_buy_when_paused(crowdsale, token_in, buyer, owner):
    amount_in = 10 ** token_in.decimals()

    crowdsale.pause({"from": owner})

    with brownie.reverts("Pausable: paused"):
        crowdsale.buy(amount_in, 0, [], {"from": buyer})


def test_token_in_limit_left(crowdsale, token_in, buyer, owner, buy_checked):
    limit_in = 5 * 10 ** token_in.decimals()
    crowdsale.setTokenInLimit(limit_in, {"from": owner})

    assert crowdsale.tokenInLimit() == limit_in

    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    crowdsale.getTokenInLimitLeft() == limit_in - amount_in


def test_buy_more_than_limit(crowdsale, owner, buyer, token_in):
    # Inputs
    limit_in = 5 * 10 ** token_in.decimals()
    crowdsale.setTokenInLimit(limit_in, {"from": owner})

    with brownie.reverts("total amount exceeded"):
        crowdsale.buy(limit_in + 1, 0, [], {"from": buyer})


def test_buy_limit_exceeded(crowdsale, owner, buyer, token_in, buy_checked):
    # Inputs
    limit_in = 5 * 10 ** token_in.decimals()
    crowdsale.setTokenInLimit(limit_in, {"from": owner})

    buy_checked(limit_in, tx_params={"from": buyer})

    with brownie.reverts("total amount exceeded"):
        crowdsale.buy(1, 0, [], {"from": buyer})


def test_buy_after_end(chain, crowdsale, token_in, buyer):
    amount_in = 10 ** token_in.decimals()

    chain.sleep(DURATION + 1)

    with brownie.reverts("TokenSale: already ended"):
        crowdsale.buy(amount_in, 0, [], {"from": buyer})


def test_set_guestlist(crowdsale, owner, token_in, rando, guestlist):
    tx = crowdsale.setGuestlist(guestlist, {"from": owner})

    assert len(tx.events["GuestlistUpdated"]) == 1

    event = tx.events["GuestlistUpdated"][0]
    assert event["guestlist"] == guestlist

    assert crowdsale.guestlist() == guestlist

    amount_in = 10 ** token_in.decimals()
    with brownie.reverts("not authorized"):
        crowdsale.buy(amount_in, 1, [], {"from": rando})


def test_finalize(owner, buyer, chain, token_in, buy_checked, finalize_checked):
    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    chain.sleep(DURATION)

    finalize_checked({"from": owner})


def test_finalize_before_end(crowdsale, owner, buyer, chain, token_in, buy_checked):
    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    with brownie.reverts("TokenSale: not finished"):
        crowdsale.finalize({"from": owner})

    chain.sleep(DURATION // 2)

    with brownie.reverts("TokenSale: not finished"):
        crowdsale.finalize({"from": owner})


def test_finalize_multiple(
    crowdsale, owner, buyer, chain, token_in, buy_checked, finalize_checked
):
    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    chain.sleep(DURATION)

    finalize_checked({"from": owner})

    with brownie.reverts("TokenSale: already finalized"):
        crowdsale.finalize({"from": owner})


def test_finalize_not_enough_tokens(
    crowdsale, owner, chain, token_in, buyer, buy_checked
):
    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    chain.sleep(DURATION)

    with brownie.reverts("TokenSale: not enough balance"):
        crowdsale.finalize({"from": owner})


def test_claim(
    chain,
    token_in,
    buyer,
    owner,
    buy_checked,
    get_amount_out,
    finalize_checked,
    claim_checked,
):
    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    chain.sleep(DURATION)

    finalize_checked({"from": owner})

    amount_out = get_amount_out(amount_in)
    claim_checked(amount_out, tx_params={"from": buyer})


def test_claim_multiple_buyers(
    chain,
    token_in,
    buyer,
    rando,
    owner,
    get_amount_out,
    buy_checked,
    finalize_checked,
    claim_checked,
):
    amount_in1 = 10 ** token_in.decimals()
    buy_checked(amount_in1, tx_params={"from": buyer})

    amount_in2 = 2 * 10 ** token_in.decimals()
    buy_checked(amount_in2, tx_params={"from": rando})

    chain.sleep(DURATION)

    finalize_checked({"from": owner})

    amount_out1 = get_amount_out(amount_in1)
    claim_checked(amount_out1, tx_params={"from": buyer})

    amount_out2 = get_amount_out(amount_in2)
    claim_checked(amount_out2, tx_params={"from": rando})


def test_claim_multiple_buys(
    chain,
    token_in,
    buyer,
    owner,
    get_amount_out,
    buy_checked,
    finalize_checked,
    claim_checked,
):
    amount_in1 = 10 ** token_in.decimals()
    buy_checked(amount_in1, tx_params={"from": buyer})

    amount_in2 = 2 * 10 ** token_in.decimals()
    buy_checked(amount_in2, tx_params={"from": buyer})

    chain.sleep(DURATION)

    finalize_checked({"from": owner})

    amount_out = get_amount_out(amount_in1 + amount_in2)
    claim_checked(amount_out, tx_params={"from": buyer})


def test_claim_when_paused(
    chain, crowdsale, token_in, buyer, buy_checked, finalize_checked, owner
):
    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    chain.sleep(DURATION)

    finalize_checked({"from": owner})

    crowdsale.pause({"from": owner})

    with brownie.reverts("Pausable: paused"):
        crowdsale.claim({"from": buyer})


def test_claim_before_finalize(chain, crowdsale, token_in, buyer, buy_checked):
    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    chain.sleep(DURATION)

    with brownie.reverts("sale not finalized"):
        crowdsale.claim({"from": buyer})


def test_claim_zero(
    chain, crowdsale, buyer, token_in, owner, rando, buy_checked, finalize_checked
):
    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    chain.sleep(DURATION)

    finalize_checked({"from": owner})

    with brownie.reverts("nothing to claim"):
        crowdsale.claim({"from": rando})


def test_claim_multiple(
    chain,
    crowdsale,
    buyer,
    token_in,
    owner,
    buy_checked,
    get_amount_out,
    finalize_checked,
    claim_checked,
):
    amount_in = 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    chain.sleep(DURATION)

    finalize_checked({"from": owner})

    amount_out = get_amount_out(amount_in)
    claim_checked(amount_out, tx_params={"from": buyer})

    with brownie.reverts("already claimed"):
        crowdsale.claim({"from": buyer})


def test_permissions(crowdsale, chain, rando, token_in):
    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.transferOwnership(rando, {"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.finalize({"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.setSaleStart(chain.time() + 10, {"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.setSaleDuration(1, {"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.setTokenOutPrice(1, {"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.setSaleRecipient(rando, {"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.setGuestlist(ADDRESS_ZERO, {"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.setTokenInLimit(1, {"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.sweep(token_in, {"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.pause({"from": rando})

    with brownie.reverts("Ownable: caller is not the owner"):
        crowdsale.unpause({"from": rando})


def test_sale_ended_time(crowdsale, chain):
    assert not crowdsale.saleEnded()

    chain.sleep(DURATION)
    chain.mine()

    assert crowdsale.saleEnded()


def test_sale_ended_limit(crowdsale, token_in, owner, buyer, buy_checked):
    limit_in = 5 * 10 ** token_in.decimals()

    tx = crowdsale.setTokenInLimit(limit_in, {"from": owner})

    assert len(tx.events["TokenInLimitUpdated"]) == 1

    event = tx.events["TokenInLimitUpdated"][0]
    assert event["tokenInLimit"] == limit_in

    assert not crowdsale.saleEnded()

    amount_in = 5 * 10 ** token_in.decimals()
    buy_checked(amount_in, tx_params={"from": buyer})

    assert crowdsale.saleEnded()


def test_set_sale_start(crowdsale, chain):
    assert crowdsale.saleStart() <= chain.time()

    start_time = chain.time() + 10

    tx = crowdsale.setSaleStart(start_time)

    assert len(tx.events["SaleStartUpdated"]) == 1

    event = tx.events["SaleStartUpdated"][0]
    assert event["saleStart"] == start_time

    assert crowdsale.saleStart() == start_time

    chain.sleep(start_time - chain.time())
    chain.mine()

    assert crowdsale.saleStart() <= chain.time()


def test_set_sale_duration(crowdsale, chain):
    assert not crowdsale.saleEnded()

    chain.sleep(DURATION)
    chain.mine()

    assert crowdsale.saleEnded()

    duration = 2 * DURATION

    tx = crowdsale.setSaleDuration(duration)

    assert len(tx.events["SaleDurationUpdated"]) == 1

    event = tx.events["SaleDurationUpdated"][0]
    assert event["saleDuration"] == duration

    assert crowdsale.saleDuration() == duration
    assert not crowdsale.saleEnded()


def test_set_token_out_price(crowdsale, token_in_params, buyer, buy_checked):
    token_in = token_in_params["token"]
    price = token_in_params["price"]

    amount_in = 10 ** token_in.decimals()

    amount_out1 = buy_checked(amount_in, tx_params={"from": buyer})

    new_price = 2 * price

    tx = crowdsale.setTokenOutPrice(new_price)

    assert len(tx.events["TokenOutPriceUpdated"]) == 1

    event = tx.events["TokenOutPriceUpdated"][0]
    assert event["tokenOutPrice"] == new_price

    assert crowdsale.tokenOutPrice() == new_price

    amount_out2 = buy_checked(amount_in, price=new_price, tx_params={"from": buyer})

    assert amount_out1 == 2 * amount_out2


def test_set_sale_recipient(crowdsale, token_in, buyer, rando, buy_checked):
    tx = crowdsale.setSaleRecipient(rando)

    assert len(tx.events["SaleRecipientUpdated"]) == 1

    event = tx.events["SaleRecipientUpdated"][0]
    assert event["recipient"] == rando

    assert crowdsale.saleRecipient() == rando

    amount_in = 5 * 10 ** token_in.decimals()
    buy_checked(amount_in, recipient=rando, tx_params={"from": buyer})


def test_sweep_token_out(
    crowdsale,
    ctdl,
    owner,
    buyer,
    rando,
    token_in,
    buy_checked,
    finalize_checked,
    claim_checked,
    get_amount_out,
    chain,
):
    # Inputs
    amount_in = 10 ** token_in.decimals()

    buy_checked(amount_in, tx_params={"from": buyer})
    buy_checked(amount_in, tx_params={"from": rando})

    chain.sleep(DURATION)

    extra_out = 5 * 10 ** ctdl.decimals()
    finalize_checked(extra_out=extra_out, tx_params={"from": owner})

    amount_out = get_amount_out(amount_in)
    claim_checked(amount_out, tx_params={"from": buyer})

    tx = crowdsale.sweep(ctdl, {"from": owner})

    assert len(tx.events["Sweeped"]) == 1

    event = tx.events["Sweeped"][0]
    assert event["token"] == ctdl
    assert event["amount"] == extra_out

    assert ctdl.balanceOf(owner) == extra_out
    assert (
        ctdl.balanceOf(crowdsale)
        == crowdsale.totalTokenOutBought() - crowdsale.totalTokenOutClaimed()
    )


def test_sweep_other(crowdsale, deployer, owner, token2):
    amount = 10 ** token2.decimals()
    token2.transfer(crowdsale, amount, {"from": deployer})

    crowdsale.sweep(token2, {"from": owner})

    assert token2.balanceOf(owner) == amount
