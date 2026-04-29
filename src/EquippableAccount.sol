// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC6551Account, IERC6551Executable} from "./interfaces/IERC6551.sol";
import {IERC6551Equipment} from "./interfaces/IERC6551Equipment.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/// @title  EquippableAccount — ERC-6551 Token Bound Account with ERC-8216 Equipment Slots
/// @notice Reference implementation of the IERC6551Equipment interface (v1.2),
///         providing slot-based equipment management with permanent locking,
///         mint-time and balance-only equip operations, and tamper-resistant
///         enforcement at the execute() layer.
/// @dev    ERC-8216 v1.2 (2026-04-28)
///         - Adds equipAtMint, lockSlotAtMint, equipFromBalance,
///           equipAndLockAtMint
///         - Caches isERC721 on SlotEntry at equip time; postfix integrity
///           check uses the cached value (closes the type-shifting attack)
///         - Account-bound unequip disposition — assets remain in the TBA
///         - Adds the prefix execute-target restriction in execute()
///           (closes the approval-based bypass)
///
///         Binding pattern (bytecode-suffix):
///         ----------------------------------
///         (chainId, tokenContract, tokenId) is read directly from this
///         proxy's immutable bytecode suffix appended by the canonical
///         ERC-6551 Registry at deploy time. The `token()` function below
///         issues a single extcodecopy at offset 0x4d, length 0x60.
///
///         Spec Security Considerations (under "Parent-contract gating is
///         bytecode-derived") permits a stored-binding pattern (constructor-
///         or initializer-set storage) provided that `token()` returns
///         identical values regardless of caller and that the binding is set
///         exactly once. The bytecode-suffix path is preferred here because
///         it inherits its immutability from the canonical 6551 binding and
///         requires no additional defense — there is no storage location to
///         compromise via uninitialized initializer, governance, upgrade, or
///         delegatecall. Implementations that need a different binding
///         pattern (custom registries, test harnesses) MAY substitute a
///         stored-binding `token()` and remove this comment.
contract EquippableAccount is
    IERC6551Account,
    IERC6551Executable,
    IERC6551Equipment,
    ERC1155Holder,
    ERC721Holder
{
    // ── Storage ──

    uint256 private _state;
    mapping(bytes32 => SlotEntry) private _slots;
    bytes32[] private _occupiedSlots;
    mapping(bytes32 => uint256) private _slotIndex;

    // ── Constants ──

    /// @notice RECOMMENDED upper bound on simultaneously occupied slots. The
    ///         execute-layer prefix and postfix checks both iterate occupied
    ///         slots — bounding the count bounds per-execute gas.
    uint256 public constant MAX_OCCUPIED_SLOTS = 64;

    // ── Errors ──

    error NotAuthorized();
    error OnlyParentContract();
    error SlotAlreadyOccupied(bytes32 slotId);
    error SlotEmpty(bytes32 slotId);
    error SlotIsLocked(bytes32 slotId);
    error SlotAlreadyLocked(bytes32 slotId);
    error SlotIntegrityViolated(bytes32 slotId);
    error InsufficientTBABalance(bytes32 slotId);
    error ExecuteIntoEquippedContract(address to);
    error InvalidAmount();
    error ArrayLengthMismatch();
    error UnsupportedOperation(uint8 op);
    error ExecutionFailed(bytes result);
    error MaxSlotsExceeded();

    // ── Modifiers ──

    modifier onlyOwner() {
        if (!_isValidSigner(msg.sender)) revert NotAuthorized();
        _;
    }

    /// @dev Restrict to the parent contract address read from the canonical
    ///      6551 `token()` function. With bytecode-suffix binding the value
    ///      is mathematically immutable from deploy time.
    modifier onlyParentContract() {
        (, address tokenContract,) = token();
        if (msg.sender != tokenContract) revert OnlyParentContract();
        _;
    }

    // ── ERC-6551 Account ──

    receive() external payable override {}

    /// @notice Read (chainId, tokenContract, tokenId) from this proxy's
    ///         immutable bytecode suffix appended by the canonical registry.
    function token()
        public
        view
        override
        returns (uint256 chainId, address tokenContract, uint256 tokenId)
    {
        bytes memory footer = new bytes(0x60);
        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }
        return abi.decode(footer, (uint256, address, uint256));
    }

    function state() external view override returns (uint256) {
        return _state;
    }

    function isValidSigner(address signer, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        if (_isValidSigner(signer)) {
            return IERC6551Account.isValidSigner.selector;
        }
        return bytes4(0);
    }

    // ── ERC-6551 Execution ──

    /// @notice Execute an arbitrary call on behalf of the TBA.
    /// @dev    Two-stage equipment integrity:
    ///         (1) PREFIX — refuse to dispatch any call into a contract that
    ///             currently appears as `tokenContract` of an occupied slot.
    ///             Closes the approval-based bypass where execute() could be
    ///             used to grant standing rights against equipped tokens.
    ///         (2) POSTFIX — after the external call returns successfully,
    ///             verify every equipped token is still physically held by
    ///             this account. Closes the direct-transfer bypass.
    ///
    ///         CEI: ++_state happens before the external call.
    function execute(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) external payable override onlyOwner returns (bytes memory result) {
        if (operation != 0) revert UnsupportedOperation(operation);

        uint256 occ = _occupiedSlots.length;
        for (uint256 i; i < occ; ++i) {
            if (to == _slots[_occupiedSlots[i]].tokenContract) {
                revert ExecuteIntoEquippedContract(to);
            }
        }

        ++_state;

        bool success;
        (success, result) = to.call{value: value}(data);
        if (!success) revert ExecutionFailed(result);

        _verifyEquipmentInvariant();
    }

    // ── IERC6551Equipment — Single Operations ──

    function equip(
        bytes32 slotId,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    ) external override onlyOwner {
        _equip(slotId, tokenContract, tokenId, amount);
    }

    function unequip(bytes32 slotId) external override onlyOwner {
        _unequip(slotId);
    }

    function lockSlot(bytes32 slotId) external override onlyOwner {
        _lockSlot(slotId);
    }

    // ── IERC6551Equipment — Batch Operations ──

    function equipBatch(
        bytes32[] calldata slotIds,
        address[] calldata tokenContracts,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external override onlyOwner {
        if (
            slotIds.length != tokenContracts.length ||
            slotIds.length != tokenIds.length ||
            slotIds.length != amounts.length
        ) revert ArrayLengthMismatch();

        for (uint256 i; i < slotIds.length; ++i) {
            _equip(slotIds[i], tokenContracts[i], tokenIds[i], amounts[i]);
        }
    }

    function lockSlots(bytes32[] calldata slotIds) external override onlyOwner {
        for (uint256 i; i < slotIds.length; ++i) {
            _lockSlot(slotIds[i]);
        }
    }

    // ── IERC6551Equipment — Mint-time + balance-only operations ──

    function equipAtMint(
        bytes32 slotId,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    ) external override onlyParentContract {
        _equipFromTBABalance(slotId, tokenContract, tokenId, amount);
    }

    function lockSlotAtMint(bytes32 slotId) external override onlyParentContract {
        _lockSlot(slotId);
    }

    function equipFromBalance(
        bytes32 slotId,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    ) external override onlyOwner {
        _equipFromTBABalance(slotId, tokenContract, tokenId, amount);
    }

    function equipAndLockAtMint(
        bytes32 slotId,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    ) external override onlyParentContract {
        _equipFromTBABalance(slotId, tokenContract, tokenId, amount);
        _slots[slotId].locked = true;
        ++_state;
        emit SlotLocked(slotId, tokenContract, tokenId);
    }

    // ── IERC6551Equipment — Views ──

    function getEquipped(bytes32 slotId)
        external
        view
        override
        returns (address tokenContract, uint256 tokenId, uint256 amount)
    {
        SlotEntry memory entry = _slots[slotId];
        return (entry.tokenContract, entry.tokenId, entry.amount);
    }

    function getLoadout()
        external
        view
        override
        returns (SlotEntry[] memory entries)
    {
        uint256 len = _occupiedSlots.length;
        entries = new SlotEntry[](len);
        for (uint256 i; i < len; ++i) {
            entries[i] = _slots[_occupiedSlots[i]];
        }
    }

    function isSlotOccupied(bytes32 slotId) external view override returns (bool) {
        return _slotIndex[slotId] != 0;
    }

    function isSlotLocked(bytes32 slotId) external view override returns (bool) {
        return _slots[slotId].locked;
    }

    // ── ERC-165 ──

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Holder)
        returns (bool)
    {
        return
            interfaceId == type(IERC6551Account).interfaceId ||
            interfaceId == type(IERC6551Executable).interfaceId ||
            interfaceId == type(IERC6551Equipment).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ── Internal: Equipment Logic ──

    /// @dev Standard equip with wallet-to-TBA transfer. Token type is
    ///      detected ONCE here via ERC-165 probe and cached on the slot
    ///      entry. All later operations consult the cached value — never
    ///      re-probe.
    function _equip(
        bytes32 slotId,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    ) internal {
        if (_slots[slotId].locked) revert SlotIsLocked(slotId);
        if (_slotIndex[slotId] != 0) revert SlotAlreadyOccupied(slotId);
        if (amount == 0) revert InvalidAmount();
        if (_occupiedSlots.length >= MAX_OCCUPIED_SLOTS) revert MaxSlotsExceeded();

        bool tokenIs721 = _isERC721(tokenContract);
        if (tokenIs721 && amount != 1) revert InvalidAmount();

        _slots[slotId] = SlotEntry({
            slotId: slotId,
            tokenContract: tokenContract,
            tokenId: tokenId,
            amount: amount,
            locked: false,
            isERC721: tokenIs721
        });

        _occupiedSlots.push(slotId);
        _slotIndex[slotId] = _occupiedSlots.length;

        ++_state;

        if (tokenIs721) {
            IERC721(tokenContract).safeTransferFrom(msg.sender, address(this), tokenId);
        } else {
            IERC1155(tokenContract).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        }

        emit Equipped(slotId, tokenContract, tokenId, amount);
    }

    /// @dev Account-bound unequip disposition — the asset remains in the TBA
    ///      after the slot is cleared. Symmetric with `equipFromBalance`,
    ///      which is the path owners use to slot a TBA-resident asset back
    ///      into a different (or the same, after some other state change)
    ///      slot. Owner-bound implementations would instead transfer the
    ///      asset to the caller here:
    ///
    ///          if (entry.isERC721) {
    ///              IERC721(entry.tokenContract).safeTransferFrom(
    ///                  address(this), msg.sender, entry.tokenId
    ///              );
    ///          } else {
    ///              IERC1155(entry.tokenContract).safeTransferFrom(
    ///                  address(this), msg.sender, entry.tokenId, entry.amount, ""
    ///              );
    ///          }
    ///
    ///      The spec leaves disposition implementation-defined; both
    ///      patterns are conformant. See the Rationale section of ERC-8216.
    function _unequip(bytes32 slotId) internal {
        if (_slots[slotId].locked) revert SlotIsLocked(slotId);
        uint256 idx = _slotIndex[slotId];
        if (idx == 0) revert SlotEmpty(slotId);

        SlotEntry memory entry = _slots[slotId];

        uint256 lastIdx = _occupiedSlots.length - 1;
        if (idx - 1 != lastIdx) {
            bytes32 lastSlot = _occupiedSlots[lastIdx];
            _occupiedSlots[idx - 1] = lastSlot;
            _slotIndex[lastSlot] = idx;
        }
        _occupiedSlots.pop();
        delete _slotIndex[slotId];
        delete _slots[slotId];

        ++_state;

        // Account-bound: asset remains in the TBA balance after slot clear.

        emit Unequipped(slotId, entry.tokenContract, entry.tokenId, entry.amount);
    }

    /// @dev Shared body of `equipAtMint`, `equipFromBalance`, and
    ///      `equipAndLockAtMint`. Registers a slot pointing at an asset the
    ///      TBA already holds, with no transfer. Access control is the
    ///      responsibility of the external entry point.
    function _equipFromTBABalance(
        bytes32 slotId,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    ) internal {
        if (_slots[slotId].locked) revert SlotIsLocked(slotId);
        if (_slotIndex[slotId] != 0) revert SlotAlreadyOccupied(slotId);
        if (amount == 0) revert InvalidAmount();
        if (_occupiedSlots.length >= MAX_OCCUPIED_SLOTS) revert MaxSlotsExceeded();

        bool tokenIs721 = _isERC721(tokenContract);
        if (tokenIs721 && amount != 1) revert InvalidAmount();

        if (tokenIs721) {
            if (IERC721(tokenContract).ownerOf(tokenId) != address(this)) {
                revert InsufficientTBABalance(slotId);
            }
        } else {
            if (IERC1155(tokenContract).balanceOf(address(this), tokenId) < amount) {
                revert InsufficientTBABalance(slotId);
            }
        }

        _slots[slotId] = SlotEntry({
            slotId: slotId,
            tokenContract: tokenContract,
            tokenId: tokenId,
            amount: amount,
            locked: false,
            isERC721: tokenIs721
        });

        _occupiedSlots.push(slotId);
        _slotIndex[slotId] = _occupiedSlots.length;

        ++_state;

        emit Equipped(slotId, tokenContract, tokenId, amount);
    }

    function _lockSlot(bytes32 slotId) internal {
        if (_slotIndex[slotId] == 0) revert SlotEmpty(slotId);
        if (_slots[slotId].locked) revert SlotAlreadyLocked(slotId);

        _slots[slotId].locked = true;
        ++_state;

        SlotEntry memory entry = _slots[slotId];
        emit SlotLocked(slotId, entry.tokenContract, entry.tokenId);
    }

    // ── Internal: Validation ──

    function _isValidSigner(address signer) internal view returns (bool) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        if (chainId != block.chainid) return false;
        return IERC721(tokenContract).ownerOf(tokenId) == signer;
    }

    function _isERC721(address tokenContract) internal view returns (bool) {
        try IERC165(tokenContract).supportsInterface(type(IERC721).interfaceId) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    /// @dev Postfix integrity check. Reads the cached `isERC721` field on
    ///      each slot entry rather than re-probing the token contract —
    ///      re-probing would open the type-shifting attack documented in
    ///      Security Considerations.
    function _verifyEquipmentInvariant() internal view {
        uint256 len = _occupiedSlots.length;
        for (uint256 i; i < len; ++i) {
            bytes32 slotId = _occupiedSlots[i];
            SlotEntry memory entry = _slots[slotId];

            if (entry.isERC721) {
                if (IERC721(entry.tokenContract).ownerOf(entry.tokenId) != address(this)) {
                    revert SlotIntegrityViolated(slotId);
                }
            } else {
                if (
                    IERC1155(entry.tokenContract).balanceOf(address(this), entry.tokenId)
                        < entry.amount
                ) {
                    revert SlotIntegrityViolated(slotId);
                }
            }
        }
    }
}
