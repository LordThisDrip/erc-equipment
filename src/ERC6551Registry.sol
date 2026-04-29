// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC6551Registry} from "./interfaces/IERC6551.sol";

/// @title ERC-6551 Registry — vendored canonical singleton
/// @notice Source-vendored copy of the canonical ERC-6551 Registry, originally
///         deployed at 0x000000006551c19487814612e58FE06813775758. Vendored
///         here so this reference repo is self-contained and so the
///         bytecode-suffix binding read by EquippableAccount.token() is
///         produced by the canonical proxy layout.
/// @dev    Reference: https://github.com/erc6551/reference
///
///         This implementation uses a Solidity-readable construction of the
///         init code rather than the heavily-optimized assembly version of
///         the on-chain canonical Registry. Both produce byte-identical
///         init code, byte-identical proxy runtime, and (given the same
///         (implementation, salt, chainId, tokenContract, tokenId)) byte-
///         identical CREATE2 addresses. The readable form trades a few
///         hundred gas per createAccount for a substantially clearer audit
///         surface, which is the right trade-off for a reference repo.
///
///         Each TBA proxy is a 173-byte runtime:
///           offset 0x00..0x0a (10 bytes): ERC-1167 prefix
///                                           363d3d373d3d3d363d73 (last byte is PUSH20)
///           offset 0x0a..0x1e (20 bytes): implementation address (PUSH20 immediate)
///           offset 0x1e..0x2d (15 bytes): ERC-1167 footer
///                                           5af43d82803e903d91602b57fd5bf3
///           offset 0x2d        (32 bytes): salt
///           offset 0x4d        (32 bytes): chainId
///           offset 0x6d        (32 bytes): tokenContract (left-padded address)
///           offset 0x8d        (32 bytes): tokenId
///         EquippableAccount.token() reads (chainId, tokenContract, tokenId)
///         in a single extcodecopy at offset 0x4d, length 0x60.
contract ERC6551Registry is IERC6551Registry {
    error AccountCreationFailed();

    bytes private constant DEPLOY_HEADER  = hex"3d60ad80600a3d3981f3";
    bytes private constant PROXY_PREFIX   = hex"363d3d373d3d3d363d73";
    bytes private constant PROXY_FOOTER   = hex"5af43d82803e903d91602b57fd5bf3";

    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external override returns (address acct) {
        bytes memory initCode = _initCode(implementation, salt, chainId, tokenContract, tokenId);

        bytes32 initHash = keccak256(initCode);
        address computed = address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, initHash)
        ))));

        if (computed.code.length == 0) {
            assembly {
                acct := create2(0, add(initCode, 0x20), mload(initCode), salt)
            }
            if (acct == address(0)) revert AccountCreationFailed();
            emit ERC6551AccountCreated(acct, implementation, salt, chainId, tokenContract, tokenId);
        } else {
            acct = computed;
        }
    }

    function account(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external view override returns (address) {
        bytes memory initCode = _initCode(implementation, salt, chainId, tokenContract, tokenId);
        bytes32 initHash = keccak256(initCode);
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, initHash)
        ))));
    }

    /// @dev Build the 183-byte init code for a TBA proxy. Total breakdown:
    ///      10 (deploy header) + 10 (proxy prefix) + 20 (impl) + 15 (footer)
    ///      + 32 (salt) + 32 (chainId) + 32 (tokenContract) + 32 (tokenId)
    ///      = 183 bytes; runtime returned by deploy header is 173 bytes
    ///      (the trailing 173 bytes of the init code).
    function _initCode(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) private pure returns (bytes memory) {
        return abi.encodePacked(
            DEPLOY_HEADER,
            PROXY_PREFIX,
            implementation,
            PROXY_FOOTER,
            salt,
            chainId,
            uint256(uint160(tokenContract)),
            tokenId
        );
    }
}
