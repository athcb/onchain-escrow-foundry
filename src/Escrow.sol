// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
* @title Escrow Contract
* @notice This contract implements an escrow service for buyers and sellers.
* @dev 
* - This contract allows a buyer to deposit funds into escrow for a purchase, with an arbiter to complete the transaction.
* - The funds are held until the arbiter marks the purchase as complete. 
* - Allows for partial deposits and cancellation of the escrow if 24 hours have passed after the deposit.
* - Uses a mapping to store the purchase details and a unique purchase ID is created using the buyer's address and the item ID.
* - Does not allow for the same item to be in multiple escrows at the same time.
* - Emits events for new escrows, deposits, completions, and cancellations.
 */


contract Escrow is ReentrancyGuard {

    enum EscrowStatus { NotCreated, Created, PartlyDeposited, Deposited, Completed, Cancelled }
    
    // store the purchase details:
    struct Purchase {
        address buyer;
        address seller;
        address arbiter;
        uint256 itemId;
        uint256 price;
        uint256 escrowBalance;
        EscrowStatus status;
        uint createdAt;
        uint depositedAt;
        uint completedAt;
        uint cancelledAt;
    }

    // map a unique purchaseId based on the buyer and itemId to the Purchase details:
    mapping(bytes32 => Purchase) public purchases;

    // map the itemId to the EscrowStatus (so that one item cannot be in multiple escrows):
    mapping(uint => bool) public isItemInEscrow;


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


    constructor() {}

     // fallback function to prevent direct deposits:
    receive() external payable {
        revert("Direct deposits not allowed");
    }

    function newEscrow(
        address buyer, 
        address seller, 
        address arbiter, 
        uint256 itemId, 
        uint256 price
    ) external {

        require(!isItemInEscrow[itemId], "Item already in escrow");
        require(buyer != address(0), "Invalid buyer");
        require(seller != address(0), "Invalid seller");
        require(arbiter != address(0), "Invalid arbiter");
        require(price > 0, "Price must be greater than zero");

        // create the unique purchase identifier linking the buyer and itemId:
        bytes32 purchaseId = getPurchaseId(buyer, itemId);

        // create a reference to the Purchase struct for the purchaseId:
        Purchase storage purchase = purchases[purchaseId];

        require(msg.sender == arbiter || 
                msg.sender == buyer, 
                "Only arbiter or buyer can create escrow");

        require(purchase.status == EscrowStatus.NotCreated, "Escrow already created");
        
        // add a new Escrow entry in the mapping for the purchaseId:
        purchase.buyer = buyer;
        purchase.seller = seller;
        purchase.arbiter = arbiter;
        purchase.itemId = itemId;
        purchase.price = price;
        purchase.status = EscrowStatus.Created;
        purchase.createdAt = block.timestamp;

        // update the item state:
        isItemInEscrow[itemId] = true;

        emit NewEscrow(buyer, seller, itemId, price);
        
    }

    function deposit(uint256 itemId) external payable {

        // re-create the unique purchase Id with the msg.sender as the buyer and the itemID:
        bytes32 purchaseId =  getPurchaseId(msg.sender, itemId);

        // create a reference to the Purchase struct for the purchaseId:
        Purchase storage purchase = purchases[purchaseId];

        // perform security checks:
        require(msg.sender == purchase.buyer, "Only the buyer can deposit");
        require(purchase.status == EscrowStatus.Created ||
                purchase.status == EscrowStatus.PartlyDeposited, "Escrow not in correct state");

        // check if the deposit amount is correct:
        require(purchase.escrowBalance + msg.value <= purchase.price,  "Deposit exceeds price");
        require(msg.value > 0, "Deposit must be greater than zero");
        
        // transfer the funds to the contract:
        purchase.escrowBalance += msg.value;

        // flag the purchase as deposited or partly deposited:
        if(purchase.escrowBalance == purchase.price) {
            purchase.status = EscrowStatus.Deposited;
            emit Deposit(msg.sender, itemId, msg.value, "complete");

        } else if (purchase.escrowBalance < purchase.price) {
            purchase.status = EscrowStatus.PartlyDeposited;
            emit Deposit(msg.sender, itemId, msg.value, "partial");
        }

        // set the deposit time:
        purchase.depositedAt = block.timestamp;

    }

    function completePurchase(address buyer, uint itemId) external nonReentrant {

        // re-create the unique purchase Id with the msg.sender as the buyer and the itemID:
        bytes32 purchaseId = getPurchaseId(buyer, itemId);

        // create a reference to the Purchase struct for the purchaseId:
        Purchase storage purchase = purchases[purchaseId];

        // perform security checks:
        require(msg.sender == purchase.arbiter, "Only arbiter can complete the purchase");
        require(purchase.status == EscrowStatus.Deposited,  "Escrow not in correct state");
        require(purchase.price == purchase.escrowBalance,  "Price and balance mismatch");
        
        uint256 transferAmount = purchase.escrowBalance; 

        // update state:
        purchase.status = EscrowStatus.Completed;
        purchase.escrowBalance = 0;
        purchase.completedAt = block.timestamp;

        // transfer the funds to the seller:
        (bool success, ) = purchase.seller.call{ value: transferAmount }("");
        require(success, "Transfer failed");
        
        // emit the Complete event:
        emit Complete(buyer, itemId);
    }

    // refund deposit if escrow is not completed:
    function cancel(uint itemId) external nonReentrant {

        // re-create the unique purchase Id with the msg.sender as the buyer and the itemID:
        bytes32 purchaseId = getPurchaseId(msg.sender, itemId);

        // ceate a reference to the Purchase struct for the purchaseId:
        Purchase storage purchase = purchases[purchaseId];

        // perform security checks:
        require(msg.sender == purchase.buyer, "Only buyer can request cancellation");
        require(purchase.status == EscrowStatus.Created || 
                purchase.status == EscrowStatus.Deposited ||
                purchase.status == EscrowStatus.PartlyDeposited,  
                "Escrow not in correct state");  
        require(block.timestamp > purchase.depositedAt + 1 days, "Cancellation not allowed within 24 hours of deposit");  

        uint256 refundAmount = purchase.escrowBalance;

        // update state
        purchase.status = EscrowStatus.Cancelled;
        isItemInEscrow[itemId] = false;
        purchase.escrowBalance = 0;
        purchase.cancelledAt = block.timestamp;

        // transfer the funds back to the buyer if a full or partial deposit was made:
        if(refundAmount > 0) {

            // refund buyer
            (bool success, ) = purchase.buyer.call{ value: refundAmount }("");
            require(success, "Transfer failed");

        }
        
        // emit the Cancel event:
        emit Cancel(msg.sender, itemId);
    }

    function getPurchaseId(address buyer, uint itemId) internal pure returns (bytes32) {

        return keccak256(abi.encode(buyer, itemId));
    }

}