// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IERC6551Equipment — Slot-Based Equipment for Token Bound Accounts
/// @notice A standard interface for equipping and unequipping tokens
///         within ERC-6551 Token Bound Accounts using named slots.
/// @dev    This interface extends ERC-6551 accounts with composable
///         equipment management. Slots are identified by bytes32 keys,
///         allowing any application to define its own slot taxonomy
///         (e.g., gaming loadouts, social profile badges, identity credentials).
///
///         Slots may optionally be locked, making them permanently immutable.
///         This enables use cases like locked identity traits, soulbound badges,
///         or permanent race/class assignments in games.
///
///         The ERC-165 identifier for this interface is 0xTBD.

interface IERC6551Equipment {

    /// @notice Metadata describing an occupied equipment slot.
    struct SlotEntry {
        bytes32 slotId;        // Application-defined slot identifier
        address tokenContract; // Address of the equipped token contract
        uint256 tokenId;       // Token ID of the equipped token
        uint256 amount;        // Amount equipped (1 for ERC-721, ≥1 for ERC-1155)
    }

    /// @notice Emitted when a token is equipped into a slot.
    event Equipped(
        bytes32 indexed slotId,
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 amount
    );

    /// @notice Emitted when a token is removed from a slot.
    event Unequipped(
        bytes32 indexed slotId,
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 amount
    );

    /// @notice Emitted when a slot is permanently locked.
    /// @param slotId         The slot that was locked.
    /// @param tokenContract  The token contract locked in the slot.
    /// @param tokenId        The token ID locked in the slot.
    event SlotLocked(
        bytes32 indexed slotId,
        address indexed tokenContract,
        uint256 tokenId
    );

    /// @notice Equip a token into the specified slot.
    /// @dev    MUST revert if the caller is not a valid signer for this account.
    ///         MUST revert if the slot is already occupied (call unequip first).
    ///         MUST revert if the slot is locked.
    ///         MUST transfer the token from the caller into this account.
    ///         MUST emit the {Equipped} event.
    function equip(
        bytes32 slotId,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    ) external;

    /// @notice Remove the token currently in the specified slot.
    /// @dev    MUST revert if the caller is not a valid signer for this account.
    ///         MUST revert if the slot is empty.
    ///         MUST revert if the slot is locked.
    ///         MUST transfer the token from this account back to the caller.
    ///         MUST emit the {Unequipped} event.
    function unequip(bytes32 slotId) external;

    /// @notice Permanently lock a slot, preventing future equip/unequip.
    /// @dev    MUST revert if the caller is not a valid signer for this account.
    ///         MUST revert if the slot is empty.
    ///         MUST revert if the slot is already locked.
    ///         MUST emit the {SlotLocked} event.
    ///         This action is irreversible. Locked slots persist across
    ///         ownership transfers of the parent NFT.
    function lockSlot(bytes32 slotId) external;

    /// @notice Query what is currently equipped in a given slot.
    function getEquipped(bytes32 slotId)
        external
        view
        returns (address tokenContract, uint256 tokenId, uint256 amount);

    /// @notice Return the full loadout — all currently occupied slots.
    function getLoadout()
        external
        view
        returns (SlotEntry[] memory entries);

    /// @notice Check whether a slot is currently occupied.
    function isSlotOccupied(bytes32 slotId) external view returns (bool);

    /// @notice Check whether a slot is permanently locked.
    /// @dev    Locked slots cannot be equipped or unequipped.
    ///         Locks persist across ownership transfers.
    function isSlotLocked(bytes32 slotId) external view returns (bool);
}
