// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC6551Registry} from "./interfaces/IERC6551.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

interface IInitializable6551 {
    function initialize(uint256 chainId, address tokenContract, uint256 tokenId) external;
}

contract ERC6551Registry is IERC6551Registry {
    error AccountCreationFailed();

    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external override returns (address) {
        bytes32 _salt = keccak256(abi.encode(salt, chainId, tokenContract, tokenId));

        address acct = Clones.cloneDeterministic(implementation, _salt);
        IInitializable6551(acct).initialize(chainId, tokenContract, tokenId);

        emit ERC6551AccountCreated(acct, implementation, salt, chainId, tokenContract, tokenId);
        return acct;
    }

    function account(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external view override returns (address) {
        bytes32 _salt = keccak256(abi.encode(salt, chainId, tokenContract, tokenId));
        return Clones.predictDeterministicAddress(implementation, _salt);
    }
}
