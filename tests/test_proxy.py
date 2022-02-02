import pytest
import time
from brownie import project

from conftest import ADDRESS_ZERO, DURATION, MAX_UINT256

TransparentUpgradeableProxy = project.load(
    "lib/openzeppelin-contracts"
).TransparentUpgradeableProxy


# TODO: Move to helper file or something
def deploy_proxy_and_logic(contract_container, args, proxy_admin, deployer):
    logic = contract_container.deploy({"from": deployer})

    data = logic.initialize.encode_input(*args)

    proxy = TransparentUpgradeableProxy.deploy(
        logic, proxy_admin, data, {"from": deployer}
    )

    time.sleep(1)

    TransparentUpgradeableProxy.remove(proxy)
    proxy = contract_container.at(proxy.address)

    return proxy


@pytest.fixture()
def proxy_admin(Contract):
    yield Contract("0x20Dce41Acca85E8222D6861Aa6D23B6C941777bF")


@pytest.fixture()
def proxy(
    TokenSaleUpgradeable, chain, owner, ctdl, treasury, token_in_params, proxy_admin
):
    token_sale = TokenSaleUpgradeable.deploy({"from": owner})
    token_in = token_in_params["token"]
    args = [
        ctdl,  # tokenOut
        token_in,  # tokenIn
        chain.time() + 10,  # saleStart
        DURATION,  # saleDuration
        token_in_params["price"],  # tokenOutPrice
        treasury,  # saleRecipient
        ADDRESS_ZERO,  # guestlist
        MAX_UINT256,  # tokenInLimit
    ]

    token_sale = deploy_proxy_and_logic(
        TokenSaleUpgradeable, args, proxy_admin=proxy_admin, deployer=owner
    )

    chain.sleep(10)
    yield token_sale


@pytest.fixture()
def new_logic(TokenSaleUpgradeable, owner):
    yield TokenSaleUpgradeable.deploy({"from": owner})


def test_proxy_slot(web3, proxy, proxy_admin):
    # ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
    ADMIN_SLOT = 0xB53127684A568B3173AE13B9F8A6016E243E63B6E8EE1178D6A717850B5D6103
    admin = web3.toChecksumAddress(web3.eth.getStorageAt(proxy.address, ADMIN_SLOT))

    assert admin == proxy_admin


def test_upgrade(proxy_admin, proxy, new_logic):
    proxy_admin_owner = proxy_admin.owner()

    # Storage
    owner = proxy.owner()

    tokenIn = proxy.owner()
    tokenOut = proxy.owner()
    saleStart = proxy.owner()
    saleDuration = proxy.owner()
    saleRecipient = proxy.saleRecipient()
    finalized = proxy.finalized()

    tokenOutPrice = proxy.tokenOutPrice()
    totalTokenIn = proxy.totalTokenIn()
    totalTokenOutBought = proxy.totalTokenOutBought()
    totalTokenOutClaimed = proxy.totalTokenOutClaimed()

    tokenInLimit = proxy.tokenInLimit()

    proxy_admin.upgrade(proxy, new_logic, {"from": proxy_admin_owner})

    # Verify storage (not really necessary but just to be safe)
    assert owner == proxy.owner()

    assert tokenIn == proxy.owner()
    assert tokenOut == proxy.owner()
    assert saleStart == proxy.owner()
    assert saleDuration == proxy.owner()
    assert saleRecipient == proxy.saleRecipient()
    assert finalized == proxy.finalized()

    assert tokenOutPrice == proxy.tokenOutPrice()
    assert totalTokenIn == proxy.totalTokenIn()
    assert totalTokenOutBought == proxy.totalTokenOutBought()
    assert totalTokenOutClaimed == proxy.totalTokenOutClaimed()

    assert tokenInLimit == proxy.tokenInLimit()
