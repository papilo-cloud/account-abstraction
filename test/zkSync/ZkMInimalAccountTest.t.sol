// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZKMinimalAccount} from "src/zkSync/ZKMinimalAccount.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MemoryTransactionHelper, Transaction} from "@foundry-era/contracts/libraries/MemoryTransactionHelper.sol";
import { BOOTLOADER_FORMAL_ADDRESS } from "@foundry-era/contracts/Constants.sol";
import { ACCOUNT_VALIDATION_SUCCESS_MAGIC } from "@foundry-era/contracts/interfaces/IAccount.sol";
// import {ZkSyncChainChecker} from "lib/foundry-devops/src/ZkSyncChainChecker.sol";

contract ZkMinimalAccountTest is Test {
    ZKMinimalAccount minAccount;
    ERC20Mock usdc;

    uint256 private constant AMOUNT = 1e18;
    bytes32 constant EMPTY_BYTES32 = bytes32(0);
    address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        minAccount = new ZKMinimalAccount();
        minAccount.transferOwnership(ANVIL_DEFAULT_ACCOUNT);
        usdc = new ERC20Mock();
        vm.deal(address(minAccount), AMOUNT);
    }

    function testZkOwnerCanExecuteCommand() public {
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector, address(minAccount), AMOUNT);
        
        Transaction memory transaction = 
            _createUnsignedTransaction(minAccount.owner(), 113, dest, value, functionData);
        
        vm.prank(minAccount.owner());
        minAccount.executeTransaction(EMPTY_BYTES32, EMPTY_BYTES32, transaction);

        assertEq(usdc.balanceOf(address(minAccount)), AMOUNT);
    }

    function testZkValidateTransaction() public {
        // Arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(
            ERC20Mock.mint.selector, address(minAccount), AMOUNT);
        Transaction memory transaction = 
            _createUnsignedTransaction(minAccount.owner(), 113, dest, value, functionData);
        transaction = _signTransaction(transaction);

        // Act
        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        bytes4 magic = minAccount.validateTransaction(EMPTY_BYTES32, EMPTY_BYTES32, transaction);
        assertEq(magic, ACCOUNT_VALIDATION_SUCCESS_MAGIC);
    }


    function _signTransaction(Transaction memory transaction) internal view returns (Transaction memory) {
        bytes32 digest = MemoryTransactionHelper.encodeHash(transaction);
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        (v, r, s) = vm.sign(ANVIL_DEFAULT_KEY, digest);
        Transaction memory signedTx = transaction;
        signedTx.signature = abi.encodePacked(r, s, v);
        return signedTx;
    }

    function _createUnsignedTransaction(
        address from,
        uint8 transactionType,
        address to,
        uint256 value,
        bytes memory data
    )
        internal view returns (Transaction memory) 
    {
        uint256 nonce = vm.getNonce(address(minAccount));
        bytes32[] memory factoryDeps = new bytes32[](0);

        return Transaction({
            txType: transactionType,
            from: uint256(uint160(from)),
            to: uint256(uint160(to)),
            gasLimit: 16777216, 
            gasPerPubdataByteLimit: 16777216,
            maxFeePerGas: 16777216,
            maxPriorityFeePerGas: 16777216,
            paymaster: 0,
            nonce: nonce,
            value: value, 
            reserved: [uint256(0), uint256(0), uint256(0), uint256(0)],
            data: data,
            signature: hex"",
            factoryDeps: factoryDeps,
            paymasterInput: hex"",
            reservedDynamic: hex""

        });
    }
}