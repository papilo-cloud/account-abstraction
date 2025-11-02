// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount} from "@foundry-era/contracts/interfaces/IAccount.sol";
import {SystemContractsCaller} from "@foundry-era/contracts/libraries/SystemContractsCaller.sol";
import {MemoryTransactionHelper, Transaction} from "@foundry-era/contracts/libraries/MemoryTransactionHelper.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT } from "@foundry-era/contracts/Constants.sol";
import { Utils } from "@foundry-era/contracts/libraries/Utils.sol";
import { INonceHolder } from "@foundry-era/contracts/interfaces/INonceHolder.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "@foundry-era/contracts/interfaces/IAccount.sol";

contract ZKMinimalAccount is IAccount, Ownable {
    error ZKMinimalAccount__NotEnoughBalance();
    error ZKMinimalAccount__NotFromBootLoader();
    error ZKMinimalAccount__NotSuccessful();
    error ZKMinimalAccount__NotFromBootLoaderOrWoner();
    error ZKMinimalAccount__FailedToPay();
    error ZKMinimalAccount__ValidationFailed();

    using MemoryTransactionHelper for Transaction;
    /**
     *
     * Phase 1 Validation
     * 1. The user sends the tx to the "zkSync API client" (sort of a "light node")
     * 2. The zkSync API client checks to see that the nonce is unique by querying the NonceHolder system contract
     * 3. The zkSync client calls validateTransaction, which MUST update the nonce
     *The zkSync API client checks the nonce is updated
     *  5. The zkSync API client calls payForTransaction, or prepareForPaymaster &
     validateAndPayForPaymasterTransaction
     *  6. The zkSync API client verifies that the bootloader gets paid
     *
     * Phase 2 Execution
     *  7. The zkSync API client passes the validated transaction to the main node / sequencer (as of today, they are
     the same)
     *  8. The main node calls executeTransaction
     *  9. If a paymaster was used, the postTransaction is called

    */

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier requireFromBootLoader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZKMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    modifier requireFromBootLoaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZKMinimalAccount__NotFromBootLoaderOrWoner();
        }
        _;
    }

    constructor() Ownable(msg.sender){}

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice must increase the nonce
     * @notice must validate the tx (check the owner signed the tx)
     * @notice also check if we have enough money in our account
     */
    function validateTransaction(bytes32, /*_txHash,*/ bytes32, /*_suggestedSignedHash,*/ Transaction memory _transaction)
        external
        payable
        requireFromBootLoader
        returns (bytes4 magic)
    {
       return _validateTransaction(_transaction);
    }

    function executeTransaction(bytes32, /*_txHash,*/ bytes32, /*_suggestedSignedHash,*/ Transaction memory _transaction)
        external
        payable
        requireFromBootLoaderOrOwner
    {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert ZKMinimalAccount__NotSuccessful();
            }
        }
    }

    function executeTransactionFromOutside(Transaction memory _transaction) external payable {
        bytes4 magic = _validateTransaction(_transaction);
        if (magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            revert ZKMinimalAccount__ValidationFailed();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(bytes32, /*_txHash,*/ bytes32, /*_suggestedSignedHash,*/ Transaction memory _transaction)
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZKMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable
    {

    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
         // Call nonceholder
        // increment nonce
        // call(x, y, z) -> system contract call
        SystemContractsCaller.systemCallWithPropagatedRevert( // this is the system call simulation
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );

        // Check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if (totalRequiredBalance > address(this).balance) {
            revert ZKMinimalAccount__NotEnoughBalance();
        } 

        // Checkc the signature
        bytes32 txHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidOwner = signer == owner();
        if (isValidOwner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }

        // return the "magic" number
        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert ZKMinimalAccount__NotSuccessful();
            }
        }
    }
}