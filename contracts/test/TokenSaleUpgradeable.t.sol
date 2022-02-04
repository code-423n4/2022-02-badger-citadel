// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "forge-std/stdlib.sol";

import "./utils/StdERC20.sol";
import "./utils/StdProxy.sol";

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import "../TokenSaleUpgradeable.sol";
import "../utils/MockERC20.sol";
import "../utils/VipGuestListUpgradeable.sol";

contract CTDL is MockERC20 {
    constructor() MockERC20("Citadel Token", "CTDL", 9) {}
}

contract TestToken is MockERC20 {
    constructor() MockERC20("Test Token", "TEST", 8) {}
}

contract TokenSaleUpgradeableTest is DSTest, stdCheats, StdProxy {
    /// ==============
    /// ===== Vm =====
    /// ==============

    Vm constant vm = Vm(HEVM_ADDRESS);
    using StdERC20 for ERC20;

    /// =====================
    /// ===== Constants =====
    /// =====================

    uint64 constant DURATION = 24 hours;

    uint256 constant TOKEN_IN_PRICE_USD = 2;
    uint256 constant TOKEN_OUT_PRICE_USD = 1;

    uint256 constant TOKEN_IN_LIMIT_USD = 10;

    address constant rando = address(uint160(uint256(keccak256("rando"))));

    /// =================
    /// ===== State =====
    /// =================

    ERC20 immutable tokenIn = ERC20(address(new TestToken()));
    ERC20 immutable tokenOut = ERC20(address(new CTDL()));

    ProxyAdmin immutable proxyAdmin = new ProxyAdmin();

    TokenSaleUpgradeable tokenSale;
    VipGuestListUpgradeable guestlist;

    address treasury = address(uint160(uint256(keccak256("treasury"))));

    uint256 price;
    uint256 tokenInLimit;

    /// ==================
    /// ===== Set up =====
    /// ==================

    function setUp() public {
        price =
            (TOKEN_OUT_PRICE_USD * 10**tokenIn.decimals()) /
            TOKEN_IN_PRICE_USD;

        tokenInLimit =
            (TOKEN_IN_LIMIT_USD * 10**tokenIn.decimals()) /
            TOKEN_IN_PRICE_USD;

        guestlist = VipGuestListUpgradeable(
            deployProxy(
                type(VipGuestListUpgradeable).creationCode,
                address(proxyAdmin),
                abi.encodeWithSelector(
                    VipGuestListUpgradeable.initialize.selector
                )
            )
        );

        tokenSale = TokenSaleUpgradeable(
            deployProxy(
                type(TokenSaleUpgradeable).creationCode,
                address(proxyAdmin),
                abi.encodeWithSelector(
                    TokenSaleUpgradeable.initialize.selector,
                    address(tokenOut),
                    address(tokenIn),
                    uint64(block.timestamp),
                    DURATION,
                    price,
                    treasury,
                    address(guestlist),
                    tokenInLimit
                )
            )
        );

        // Add this address to guestlist
        guestlist.setGuestRoot(bytes32(uint256(1)));
        address[] memory guests = new address[](1);
        bool[] memory invited = new bool[](1);
        guests[0] = address(this);
        invited[0] = true;
        guestlist.setGuests(guests, invited);
    }

    /// ======================
    /// ===== Unit Tests =====
    /// ======================

    function testInitializeMultiple() public {
        vm.expectRevert("Initializable: contract is already initialized");

        tokenSale.initialize(
            address(tokenOut),
            address(tokenIn),
            uint64(block.timestamp),
            DURATION,
            price,
            treasury,
            address(0),
            type(uint256).max
        );
    }

    function testOwner() public {
        assertEq(tokenSale.owner(), address(this));
    }

    function testTransferOwnership() public {
        address owner = address(uint160(uint256(keccak256("owner"))));
        tokenSale.transferOwnership(owner);

        assertEq(tokenSale.owner(), owner);
    }

    function testPause() public {
        tokenSale.pause();

        assertTrue(tokenSale.paused());
    }

    function testUnpause() public {
        tokenSale.pause();
        tokenSale.unpause();

        assertTrue(!tokenSale.paused());
    }

    // TODO: Probably not the best way to test this
    //       How to restrict _amountIn to a range?
    function testAmountOut(uint128 _amountIn) public {
        uint256 amountOut = tokenSale.getAmountOut(_amountIn);
        uint256 expectedOut = getAmountOut(_amountIn);

        assertEq(amountOut, expectedOut);
    }

    function testBuyFailsBeforeStart() public {
        tokenSale.setSaleStart(uint64(block.timestamp + 60));

        uint256 amountIn = 10**tokenIn.decimals();

        vm.expectRevert("TokenSale: not started");
        tokenSale.buy(amountIn, 0, new bytes32[](0));
    }

    function testBuyOnce() public {
        uint256 amountIn = 10**tokenIn.decimals();

        buyChecked(amountIn, 0, new bytes32[](0));
    }

    function testBuyTwice() public {
        uint256 amountIn = 10**tokenIn.decimals();

        uint256 expectedOut = getAmountOut(amountIn);

        uint256 amountOut1 = buyChecked(amountIn / 2, 0, new bytes32[](0));
        uint256 amountOut2 = buyChecked(amountIn / 2, 0, new bytes32[](0));

        assertEq(amountOut1 + amountOut2, expectedOut);
    }

    function testBuyZero() public {
        vm.expectRevert("_tokenInAmount should be > 0");
        tokenSale.buy(0, 0, new bytes32[](0));
    }

    function testBuyTwiceFailsForDifferentDaos() public {
        uint256 amountIn = 10**tokenIn.decimals();

        buyChecked(amountIn, 0, new bytes32[](0));

        vm.expectRevert("can't vote for multiple daos");
        tokenSale.buy(amountIn, 1, new bytes32[](0));
    }

    function testBuyFailsWhenPaused() public {
        uint256 amountIn = 10**tokenIn.decimals();

        tokenSale.pause();

        vm.expectRevert("Pausable: paused");
        tokenSale.buy(amountIn, 0, new bytes32[](0));
    }

    function testTokenInLimitLeft(uint256 _amountIn) public {
        uint256 amountIn = _amountIn % tokenInLimit;

        buyChecked(amountIn, 0, new bytes32[](0));

        assertEq(tokenSale.getTokenInLimitLeft(), tokenInLimit - amountIn);
    }

    function testBuyFailsIfMoreThanLimit() public {
        tokenIn.forceMint(tokenInLimit + 1);

        vm.expectRevert("total amount exceeded");
        tokenSale.buy(tokenInLimit + 1, 0, new bytes32[](0));
    }

    function testBuyFailsIfLimitExceeded() public {
        buyChecked(tokenInLimit, 0, new bytes32[](0));

        tokenIn.forceMint(1);

        vm.expectRevert("total amount exceeded");
        tokenSale.buy(1, 0, new bytes32[](0));
    }

    function testBuyFailsAfterEnd() public {
        uint256 amountIn = 10**tokenIn.decimals();

        skip(DURATION);

        vm.expectRevert("TokenSale: already ended");
        tokenSale.buy(amountIn, 0, new bytes32[](0));
    }

    function testBuyFailsIfNotInGuestlist() public {
        uint256 amountIn = 10**tokenIn.decimals();

        vm.startPrank(rando);
        vm.expectRevert("not authorized");
        tokenSale.buy(amountIn, 0, new bytes32[](0));
    }

    function testBuyWhenNoGuestlist() public {
        tokenSale.setGuestlist(address(0));

        uint256 amountIn = 10**tokenIn.decimals();

        buyCheckedFrom(rando, amountIn, 0, new bytes32[](0));
    }

    event GuestlistUpdated(address indexed guestlist);

    function testGuestlistUpdate() public {
        vm.expectEmit(true, false, false, false);
        emit GuestlistUpdated(address(0));

        tokenSale.setGuestlist(address(0));

        assertEq(address(tokenSale.guestlist()), address(0));
    }

    function testBuyMultipleBuyers() public {
        tokenSale.setGuestlist(address(0));

        uint256 amountIn1 = 10**tokenIn.decimals();
        uint256 amountIn2 = 2 * 10**tokenIn.decimals();

        buyChecked(amountIn1, 0, new bytes32[](0));
        buyCheckedFrom(rando, amountIn2, 0, new bytes32[](0));
    }

    function testFinalize() public {
        uint256 amountIn = 10**tokenIn.decimals();

        uint256 amountOut = buyChecked(amountIn, 0, new bytes32[](0));

        skip(DURATION);

        finalizeChecked(amountOut);
    }

    function testFinalizeFailsBeforeSaleEnds() public {
        skip(DURATION - 1);

        vm.expectRevert("TokenSale: not finished");
        tokenSale.finalize();
    }

    function testFinalizeFailsIfCalledAgain() public {
        skip(DURATION);

        finalizeChecked(0);

        vm.expectRevert("TokenSale: already finalized");
        tokenSale.finalize();
    }

    function testFinalizeFailsIfNotEnoughTokenIn() public {
        uint256 amountIn = 10**tokenIn.decimals();

        buyChecked(amountIn, 0, new bytes32[](0));

        skip(DURATION);

        vm.expectRevert("TokenSale: not enough balance");
        tokenSale.finalize();
    }

    function testClaim() public {
        uint256 amountIn = 10**tokenIn.decimals();

        uint256 amountOut = buyChecked(amountIn, 0, new bytes32[](0));

        skip(DURATION);

        finalizeChecked(amountOut);

        claimChecked(amountOut);
    }

    function testClaimMultipleBuyers() public {
        tokenSale.setGuestlist(address(0));

        uint256 amountIn1 = 10**tokenIn.decimals();
        uint256 amountIn2 = 2 * 10**tokenIn.decimals();

        uint256 amountOut1 = buyChecked(amountIn1, 0, new bytes32[](0));
        uint256 amountOut2 = buyCheckedFrom(
            rando,
            amountIn2,
            0,
            new bytes32[](0)
        );

        skip(DURATION);

        finalizeChecked(amountOut1 + amountOut2);

        claimChecked(amountOut1);
        claimCheckedFrom(rando, amountOut2);
    }

    function testClaimAfterMultipleBuys() public {
        uint256 amountIn = 10**tokenIn.decimals();

        // TODO: Do I need this?
        uint256 expectedOut = getAmountOut(amountIn);

        uint256 amountOut1 = buyChecked(amountIn / 2, 0, new bytes32[](0));
        uint256 amountOut2 = buyChecked(amountIn / 2, 0, new bytes32[](0));

        skip(DURATION);

        finalizeChecked(expectedOut);

        claimChecked(amountOut1 + amountOut2);
    }

    function testClaimFailsWhenPaused() public {
        tokenSale.pause();

        vm.expectRevert("Pausable: paused");
        tokenSale.claim();
    }

    function testClaimFailsBeforeFinalize() public {
        vm.expectRevert("sale not finalized");
        tokenSale.claim();
    }

    function testClaimFailsWhenNothingToClaim() public {
        skip(DURATION);

        finalizeChecked(0);

        vm.startPrank(rando);
        vm.expectRevert("nothing to claim");
        tokenSale.claim();
    }

    function testClaimFailsIfCalledAgain() public {
        uint256 amountIn = 10**tokenIn.decimals();

        uint256 amountOut = buyChecked(amountIn, 0, new bytes32[](0));

        skip(DURATION);

        finalizeChecked(amountOut);

        claimChecked(amountOut);

        vm.expectRevert("already claimed");
        tokenSale.claim();
    }

    // TODO: Maybe move to separate functions
    function testPermissions() public {
        vm.startPrank(rando);

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.transferOwnership(rando);

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.finalize();

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.setSaleStart(uint64(block.timestamp + 10));

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.setSaleDuration(1);

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.setTokenOutPrice(1);

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.setSaleRecipient(rando);

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.setGuestlist(address(0));

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.setTokenInLimit(1);

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.sweep(address(tokenIn));

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.pause();

        vm.expectRevert("Ownable: caller is not the owner");
        tokenSale.unpause();
    }

    function testSaleEndedAfterDuration() public {
        assertTrue(!tokenSale.saleEnded());

        skip(DURATION);

        assertTrue(tokenSale.saleEnded());
    }

    function testSaleEndedAfterLimit() public {
        buyChecked(tokenInLimit, 0, new bytes32[](0));

        assertTrue(tokenSale.saleEnded());
    }

    event SaleStartUpdated(uint64 saleStart);

    function testSetSaleStart() public {
        uint64 saleStart = uint64(block.timestamp + 10);

        vm.expectEmit(false, false, false, true);
        emit SaleStartUpdated(saleStart);

        tokenSale.setSaleStart(saleStart);

        assertEq(tokenSale.saleStart(), saleStart);
    }

    event SaleDurationUpdated(uint64 saleDuration);

    function testSetSaleDuration() public {
        uint64 saleDuration = 2 hours;

        vm.expectEmit(false, false, false, true);
        emit SaleDurationUpdated(saleDuration);

        tokenSale.setSaleDuration(saleDuration);

        assertEq(tokenSale.saleDuration(), saleDuration);
    }

    function testExtendSaleDuration() public {
        skip(DURATION);
        assertTrue(tokenSale.saleEnded());

        uint64 saleDuration = 2 * DURATION;

        tokenSale.setSaleDuration(saleDuration);

        assertTrue(!tokenSale.saleEnded());

        skip(2 * DURATION);

        assertTrue(tokenSale.saleEnded());
    }

    event TokenOutPriceUpdated(uint256 tokenOutPrice);

    function testSetTokenOutPrice() public {
        vm.expectEmit(false, false, false, true);
        emit TokenOutPriceUpdated(2 * price);

        tokenSale.setTokenOutPrice(2 * price);

        assertEq(tokenSale.tokenOutPrice(), 2 * price);
    }

    event SaleRecipientUpdated(address indexed recipient);

    function testSetSaleRecipient() public {
        vm.expectEmit(true, false, false, false);
        emit SaleRecipientUpdated(rando);

        tokenSale.setSaleRecipient(rando);

        assertEq(tokenSale.saleRecipient(), rando);
    }

    event TokenInLimitUpdated(uint256 tokenInLimit);

    function testSetTokenInLimit() public {
        uint256 newTokenInLimit = 100 * 10**tokenIn.decimals();

        vm.expectEmit(false, false, false, true);
        emit TokenInLimitUpdated(newTokenInLimit);

        tokenSale.setTokenInLimit(newTokenInLimit);

        assertEq(newTokenInLimit, tokenSale.tokenInLimit());
    }

    event Sweeped(address indexed token, uint256 amount);

    function testSweepExceptTokenOut() public {
        uint256 amountIn = 10**tokenIn.decimals();
        tokenIn.forceMint(amountIn);

        tokenIn.transfer(address(tokenSale), amountIn);

        assertEq(tokenIn.balanceOf(address(this)), 0);

        vm.expectEmit(true, false, false, true);
        emit Sweeped(address(tokenIn), amountIn);

        tokenSale.sweep(address(tokenIn));

        assertEq(tokenIn.balanceOf(address(this)), amountIn);
    }

    function testSweepTokenOut() public {
        uint256 amountIn = 10**tokenIn.decimals();

        uint256 amountOut = buyChecked(amountIn, 0, new bytes32[](0));

        skip(DURATION);

        uint256 extraMint = 2 * 10**tokenIn.decimals();
        tokenOut.forceMintTo(address(tokenSale), amountOut + extraMint);

        tokenSale.sweep(address(tokenOut));

        assertEq(tokenOut.balanceOf(address(tokenSale)), amountOut);
        assertEq(tokenOut.balanceOf(address(this)), extraMint);
    }

    /// ===========================
    /// ===== Lifecycle Tests =====
    /// ===========================

    function testBuyAfterTokenInLimitUpdated() public {
        buyChecked(tokenInLimit, 0, new bytes32[](0));

        assertEq(tokenSale.getTokenInLimitLeft(), 0);

        uint256 newTokenInLimit = 100 * 10**tokenIn.decimals();
        tokenSale.setTokenInLimit(newTokenInLimit);

        assertEq(
            tokenSale.getTokenInLimitLeft(),
            newTokenInLimit - tokenInLimit
        );

        buyChecked(1, 0, new bytes32[](0));
    }

    function testTokenOutPriceDoubledDuringSale() public {
        uint256 amountIn = 10**tokenIn.decimals();

        uint256 amountOut1 = buyChecked(amountIn / 2, 0, new bytes32[](0));

        setTokenOutPrice(2 * price);

        uint256 amountOut2 = buyChecked(amountIn / 2, 0, new bytes32[](0));

        assertEq(amountOut1, 2 * amountOut2);
    }

    function testSaleRecipientChangedDuringSale() public {
        uint256 amountIn = 10**tokenIn.decimals();

        buyChecked(amountIn / 2, 0, new bytes32[](0));

        setSaleRecipient(rando);

        buyChecked(amountIn / 2, 0, new bytes32[](0));
    }

    /// ============================
    /// ===== Internal helpers =====
    /// ============================

    function getAmountOut(uint256 _amountIn)
        internal
        returns (uint256 amountOut_)
    {
        amountOut_ = (_amountIn * 10**tokenOut.decimals()) / price;
    }

    function setTokenOutPrice(uint256 _price) internal {
        price = _price;
        tokenSale.setTokenOutPrice(_price);
    }

    function setSaleRecipient(address _saleRecipient) internal {
        treasury = _saleRecipient;
        tokenSale.setSaleRecipient(_saleRecipient);
    }

    event Sale(
        address indexed buyer,
        uint8 indexed daoId,
        uint256 amountIn,
        uint256 amountOut
    );

    function buyCheckedFrom(
        address _from,
        uint256 _amountIn,
        uint8 _daoId,
        bytes32[] memory _proof
    ) internal returns (uint256 amountOut_) {
        // Get tokenIn
        tokenIn.forceMintTo(_from, _amountIn);

        // Approve
        vm.startPrank(_from);
        tokenIn.approve(address(tokenSale), _amountIn);

        // State before
        uint256 beforeFromBalance = tokenIn.balanceOf(_from);
        uint256 beforeRecipientBalance = tokenIn.balanceOf(treasury);

        uint256 beforeBoughtAmounts = tokenSale.boughtAmounts(_from);
        uint256 beforeDaoCommitments = tokenSale.daoCommitments(_daoId);
        uint256 beforeTotalTokenIn = tokenSale.totalTokenIn();
        uint256 beforeTotalTokenOutBought = tokenSale.totalTokenOutBought();

        // Expected output
        uint256 expectedOut = getAmountOut(_amountIn);

        vm.expectEmit(true, true, false, true);
        emit Sale(_from, 0, _amountIn, expectedOut);

        amountOut_ = tokenSale.buy(_amountIn, _daoId, _proof);

        assertEq(amountOut_, expectedOut);

        assertEq(tokenIn.balanceOf(_from), beforeFromBalance - _amountIn);
        assertEq(
            tokenIn.balanceOf(treasury),
            beforeRecipientBalance + _amountIn
        );

        assertEq(
            tokenSale.boughtAmounts(_from),
            beforeBoughtAmounts + amountOut_
        );
        assertEq(
            tokenSale.daoCommitments(_daoId),
            beforeDaoCommitments + amountOut_
        );
        assertEq(tokenSale.totalTokenIn(), beforeTotalTokenIn + _amountIn);
        assertEq(
            tokenSale.totalTokenOutBought(),
            beforeTotalTokenOutBought + amountOut_
        );

        assertEq(tokenSale.daoVotedFor(_from), _daoId);

        vm.stopPrank();
    }

    function buyChecked(
        uint256 _amountIn,
        uint8 _daoId,
        bytes32[] memory _proof
    ) internal returns (uint256 amountOut_) {
        amountOut_ = buyCheckedFrom(address(this), _amountIn, _daoId, _proof);
    }

    event Finalized();

    function finalizeChecked(uint256 _expectedOut) internal {
        tokenOut.forceMintTo(address(tokenSale), _expectedOut);

        vm.expectEmit(false, false, false, false);
        emit Finalized();

        tokenSale.finalize();

        assertTrue(tokenSale.finalized());
    }

    event Claim(address indexed claimer, uint256 amount);

    function claimCheckedFrom(address _from, uint256 _expectedOut)
        internal
        returns (uint256 amountOut_)
    {
        // State before
        uint256 beforeFromBalance = tokenOut.balanceOf(_from);
        uint256 beforeTokenSaleBalance = tokenOut.balanceOf(address(tokenSale));
        uint256 beforeTokenOutClaimed = tokenSale.totalTokenOutClaimed();

        vm.prank(_from);
        vm.expectEmit(true, false, false, true);

        emit Claim(_from, _expectedOut);

        amountOut_ = tokenSale.claim();

        assertEq(amountOut_, _expectedOut);

        assertTrue(tokenSale.hasClaimed(_from));
        assertEq(
            tokenSale.totalTokenOutClaimed(),
            beforeTokenOutClaimed + amountOut_
        );

        assertEq(tokenOut.balanceOf(_from), beforeFromBalance + amountOut_);
        assertEq(
            tokenOut.balanceOf(address(tokenSale)),
            beforeTokenSaleBalance - amountOut_
        );
    }

    function claimChecked(uint256 _expectedOut)
        internal
        returns (uint256 amountOut_)
    {
        amountOut_ = claimCheckedFrom(address(this), _expectedOut);
    }
}

// TODO:
// - See if there's a way to avoid event duplication
// - Replace abi.encodeWithSelector with abi.encodeCall(..) when Contract.initialize is implemented in 0.8.12
