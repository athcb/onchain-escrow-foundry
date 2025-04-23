// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Escrow.sol";

contract EscrowTest is Test {
    
    Escrow public escrow;

    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address arbiter = makeAddr("arbiter");
    uint256 itemId = 1;
    uint256 price = 1 ether;
    
    event NewEscrow(
        address indexed buyer, 
        address indexed seller, 
        uint256 itemId, 
        uint256 price
    );

    event Deposit(
        address indexed buyer, 
        uint256 indexed itemId, 
        uint256 amount, 
        string depositType
    );

    event Complete(
        address indexed buyer, 
        uint256 indexed itemId
    );

    event Cancel(
        address indexed buyer, 
        uint256 indexed itemId
    );

    function setUp() public {
        escrow = new Escrow();
    }

    function _createNewEscrow(address _as) private {
        vm.prank(_as);
        escrow.newEscrow(buyer, seller, arbiter, itemId, price);
    }

    function _createNewDeposit(address _as, uint256 amount) private {
        vm.prank(_as);
        escrow.deposit{value: amount}(itemId);
    }

    function _getPurchaseId(address _buyer, uint256 _itemId) private pure returns (bytes32) {
        return keccak256(abi.encode(_buyer, _itemId));
    }

    function test_newEscrow_PassesWhenCalledByBuyer() public {
        _createNewEscrow(buyer);
    }

    function test_newEscrow_CreatesCorrectPurchaseDetails() public {
        _createNewEscrow(buyer);

        bytes32 purchaseId = _getPurchaseId(buyer, itemId);
        Escrow.Purchase memory purchase = escrow.getPurchaseDetails(purchaseId);

        assertEq(purchase.buyer, buyer); 
        assertEq(purchase.seller, seller);
        assertEq(purchase.arbiter, arbiter);
        assertEq(purchase.itemId, itemId);
        assertEq(purchase.price, price);
        assertEq(purchase.escrowBalance, 0);
        assertEq(uint(purchase.status), uint(Escrow.EscrowStatus.Created));     

    }

    function test_newEscrow_PassesWhenCalledByArbiter() public {
        _createNewEscrow(arbiter);
    }

    function test_newEscrow_FailsWhenCalledBySeller() public {
        vm.expectRevert("Only arbiter or buyer can create escrow");
         _createNewEscrow(seller);
    }

    function test_newEscrow_emitsEvent() public {   
        vm.expectEmit(true, true, true, true);
        emit NewEscrow(buyer, seller, itemId, price);
        _createNewEscrow(buyer);
    }

    function test_newEscrow_FailsWhenItemAlreadyInEscrow() public {
        escrow.newEscrow(address(this), seller, arbiter, itemId, price);

        vm.expectRevert("Item already in escrow");
        _createNewEscrow(buyer);
    }

    function test_deposit_FullDeposit() public {
        _createNewEscrow(buyer);
        
        vm.expectEmit(true, true, true, true);
        emit Deposit(buyer, itemId, price, "complete");
        
        hoax(buyer, price);
        escrow.deposit{value: price}(itemId);

        bytes32 purchaseId = _getPurchaseId(buyer, itemId);
        Escrow.Purchase memory purchase = escrow.getPurchaseDetails(purchaseId);

        assertEq(purchase.escrowBalance, price);
        assertEq(uint(purchase.status), uint(Escrow.EscrowStatus.Deposited));
        assert(purchase.depositedAt > 0);
        assertEq(purchase.depositedAt, block.timestamp);
        assertEq(buyer.balance, 0);

    }

    function test_deposit_PartialDeposit() public {
        _createNewEscrow(buyer);

        vm.expectEmit(true, true, true, true);
        emit Deposit(buyer, itemId, price / 2, "partial");

        hoax(buyer, price);
        escrow.deposit{value: price / 2}(itemId);
        
        bytes32 purchaseId = _getPurchaseId(buyer, itemId);
        Escrow.Purchase memory purchase = escrow.getPurchaseDetails(purchaseId);

        assertEq(purchase.escrowBalance, price / 2);
        assertEq(uint(purchase.status), uint(Escrow.EscrowStatus.PartlyDeposited));
        assert(purchase.depositedAt > 0);
        assertEq(purchase.depositedAt, block.timestamp);
        assertEq(buyer.balance, price / 2);
    }

    function test_deposit_Partial2FullDeposit() public {
        vm.deal(buyer, price);
        _createNewEscrow(buyer);

        vm.expectEmit(true, true, true, true);
        emit Deposit(buyer, itemId, price / 2, "partial");
        _createNewDeposit(buyer, price / 2 );

        vm.expectEmit(true, true, true, true);
        emit Deposit(buyer, itemId, price / 2, "complete");
        _createNewDeposit(buyer, price / 2 );
        
        bytes32 purchaseId = _getPurchaseId(buyer, itemId);
        Escrow.Purchase memory purchase = escrow.getPurchaseDetails(purchaseId);

        assertEq(purchase.escrowBalance, price);
        assertEq(uint(purchase.status), uint(Escrow.EscrowStatus.Deposited));
        assert(purchase.depositedAt > 0);
        assertEq(purchase.depositedAt, block.timestamp);
        assertEq(buyer.balance, 0);
    }

    function test_deposit_FailsWhenNotBuyer() public {
        _createNewEscrow(buyer);
        vm.expectRevert("Only the buyer can deposit");
        vm.deal(arbiter, price);
        _createNewDeposit(arbiter, price);
    }

    function test_deposit_FailsWhenDepositExceedsPrice() public {
        vm.deal(buyer, price * 2);
        _createNewEscrow(buyer);
        vm.expectRevert("Deposit exceeds price");
        _createNewDeposit(buyer, price * 2);
    }

    function test_completePurchase_PassesWhenCalledByArbiter() public {
        vm.deal(buyer, price);
        _createNewEscrow(buyer);
        _createNewDeposit(buyer, price);

        vm.expectEmit(true, true, false, false);
        emit Complete(buyer, itemId);

        vm.prank(arbiter);
        escrow.completePurchase(buyer, itemId);
        bytes32 purchaseId = _getPurchaseId(buyer, itemId);
        Escrow.Purchase memory purchase = escrow.getPurchaseDetails(purchaseId);

        assertEq(uint(purchase.status), uint(Escrow.EscrowStatus.Completed));
        assertEq(seller.balance, price);
        assertEq(buyer.balance, 0);
        assertEq(purchase.escrowBalance, 0);
        assertEq(escrow.isItemInEscrow(itemId), true);
        assert(purchase.completedAt > 0);
    }

    function test_completePurchase_FailsWhenCalledBySeller() public {
        vm.deal(buyer, price);
        _createNewEscrow(buyer);
        _createNewDeposit(buyer, price);
    
        vm.expectRevert("Only arbiter can complete the purchase");
        vm.prank(seller);
        escrow.completePurchase(buyer, itemId);

    }

    function test_completePurchase_FailsWhenPartialDeposit() public {
        vm.deal(buyer, price);
        _createNewEscrow(buyer);
        _createNewDeposit(buyer, price / 2);

        vm.expectRevert("Escrow not in correct state");
        vm.prank(arbiter);
        escrow.completePurchase(buyer, itemId);
    }

    function test_cancel_FailsBefore24Hours() public {
        vm.deal(buyer, price);
        _createNewEscrow(buyer);
        _createNewDeposit(buyer, price / 2);
    
        vm.expectRevert("Cancellation not allowed within 24 hours of deposit");
        vm.prank(buyer);
        escrow.cancel(itemId);
        
    }

    function test_cancel_PassesAfter24Hours() public {
        vm.deal(buyer, price);
        _createNewEscrow(buyer);
        _createNewDeposit(buyer, price / 2);

        vm.warp(block.timestamp + 2 days);

        vm.expectEmit(true, true, false, false);
        emit Cancel(buyer, itemId);

        vm.prank(buyer);
        escrow.cancel(itemId);

        bytes32 purchaseId = _getPurchaseId(buyer, itemId);
        Escrow.Purchase memory purchase = escrow.getPurchaseDetails(purchaseId);
        
        assertEq(uint(purchase.status), uint(Escrow.EscrowStatus.Cancelled));
        assertEq(purchase.escrowBalance, 0);
        assertEq(buyer.balance, price);
        assert(escrow.isItemInEscrow(itemId) == false);
    }

    function test_cancel_FailsWhenPurchaseCompleted() public {
        vm.deal(buyer, price);
        _createNewEscrow(buyer);
        _createNewDeposit(buyer, price);
        vm.prank(arbiter);
        escrow.completePurchase(buyer, itemId);

        vm.expectRevert("Escrow not in correct state");
        vm.prank(buyer);
        escrow.cancel(itemId);
    }

}