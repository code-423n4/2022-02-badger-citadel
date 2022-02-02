import pytest

ADDRESS_ZERO = "0x0000000000000000000000000000000000000000"
MAX_UINT256 = 2 ** 256 - 1

DURATION = 60 * 60 * 24
CTDL_PRICE_USD = 2100

TOKEN_INS = {
    "test": {
        "price_usd": 2 * CTDL_PRICE_USD,
        "decimals": 8,
        "cap": MAX_UINT256,
    },
    "wbtc": {
        "address": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
        "price_usd": 40_000,
        "cap": MAX_UINT256,
    },
    "bcrvibbtc": {
        "address": "0xaE96fF08771a109dc6650a1BdCa62F2d558E40af",
        "price_usd": 40_000,
        "cap": MAX_UINT256,
    },
    "cvx": {
        "address": "0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B",
        "price_usd": 32,
        "cap": 1_000_000 * int(1e18),
    },
    "bvecvx": {
        "address": "0xfd05D3C7fe2924020620A8bE4961bBaA747e6305",
        "price_usd": 32,
        "cap": 1_000_000 * int(1e18),
    },
}


def pytest_addoption(parser):
    parser.addoption("--tokens", action="store_true", help="run tests for live tokens")


def pytest_generate_tests(metafunc):
    if "token_key" in metafunc.fixturenames:
        if metafunc.config.option.tokens:
            metafunc.parametrize("token_key", TOKEN_INS.keys())
        else:
            metafunc.parametrize("token_key", ["test"])


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


@pytest.fixture()
def deployer(accounts):
    yield accounts[0]


@pytest.fixture()
def owner(accounts):
    yield accounts[1]


@pytest.fixture()
def buyer(accounts):
    yield accounts[2]


@pytest.fixture()
def rando(accounts):
    yield accounts[3]


@pytest.fixture()
def treasury(accounts):
    yield accounts[4]


@pytest.fixture()
def ctdl(MockERC20, deployer):
    decimals = 9
    token_out = MockERC20.deploy("Citadel Token", "CTDL", decimals, {"from": deployer})

    yield token_out


@pytest.fixture()
def token_in_params(token_key, interface, MockERC20, deployer, buyer, rando):
    config = TOKEN_INS[token_key]
    if token_key == "test":
        decimals = config["decimals"]
        token = MockERC20.deploy("Test Token", "TEST", decimals, {"from": deployer})

        # Mint
        amount = 10 * 10 ** decimals
        token.mint(amount, {"from": buyer})
        token.mint(amount, {"from": rando})

    else:
        from badger_utils.token_utils.distribute_from_whales_realtime import (
            distribute_from_whales_realtime_exact,
        )

        token = interface.ERC20(config["address"])
        decimals = token.decimals()

        # Get tokens
        amount = 10 * 10 ** decimals
        distribute_from_whales_realtime_exact(buyer, amount, [token])
        distribute_from_whales_realtime_exact(rando, amount, [token])

    yield {
        "token": token,
        "price": (CTDL_PRICE_USD * 10 ** decimals) // config["price_usd"],
        "cap": config["cap"],
    }


@pytest.fixture()
def token_in(token_in_params):
    yield token_in_params["token"]


@pytest.fixture()
def token2(MockERC20, deployer):
    decimals = 18
    token_in = MockERC20.deploy("Test Token 2", "TEST2", decimals, {"from": deployer})

    # Mint 10 tokens to buyer
    amount = 10 * 10 ** decimals
    token_in.mint(amount, {"from": deployer})

    yield token_in


# TODO: Maybe add more guestlist tests (events etc.)
@pytest.fixture()
def guestlist(VipGuestListUpgradeable, deployer, buyer):
    gl = VipGuestListUpgradeable.deploy({"from": deployer})
    gl.initialize({"from": deployer})

    gl.setGuestRoot(1, {"from": deployer})
    gl.setGuests([buyer], [True], {"from": deployer})

    yield gl
