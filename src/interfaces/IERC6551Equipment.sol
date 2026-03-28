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
    /// @param slotId         The slot the token was equipped into.
    /// @param tokenContract  The address of the equipped token contract.
    /// @param tokenId        The token ID equipped.
    /// @param amount          The amount equipped.
    event Equipped(
        bytes32 indexed slotId,
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 amount
    );

    /// @notice Emitted when a token is removed from a slot.
    /// @param slotId         The slot the token was removed from.
    /// @param tokenContract  The address of the unequipped token contract.
    /// @param tokenId        The token ID unequipped.
    /// @param amount          The amount unequipped.
    event Unequipped(
        bytes32 indexed slotId,
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 amount
    );

    /// @notice Equip a token into the specified slot.
    /// @dev    MUST revert if the caller is not a valid signer for this account.
    ///         MUST revert if the slot is already occupied (call unequip first).
    ///         MUST transfer the token from the caller into this account.
    ///         MUST emit the {Equipped} event.
    /// @param slotId         Application-defined slot identifier.
    /// @param tokenContract  Address of the ERC-721 or ERC-1155 token contract.
    /// @param tokenId        The token ID to equip.
    /// @param amount          Amount to equip (must be 1 for ERC-721).
    function equip(
        bytes32 slotId,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    ) external;

    /// @notice Remove the token currently in the specified slot.
    /// @dev    MUST revert if the caller is not a valid signer for this account.
    ///         MUST revert if the slot is empty.
    ///         MUST transfer the token from this account back to the caller.
    ///         MUST emit the {Unequipped} event.
    /// @param slotId  The slot to clear.
    function unequip(bytes32 slotId) external;

    /// @notice Query what is currently equipped in a given slot.
    /// @param slotId  The slot to query.
    /// @return tokenContract  Address of the equipped token (address(0) if empty).
    /// @return tokenId        Token ID equipped (0 if empty).
    /// @return amount          Amount equipped (0 if empty).
    function getEquipped(bytes32 slotId)
        external
        view
        returns (address tokenContract, uint256 tokenId, uint256 amount);

    /// @notice Return the full loadout — all currently occupied slots.
    /// @return entries  Array of SlotEntry structs for every occupied slot.
    function getLoadout()
        external
        view
        returns (SlotEntry[] memory entries);

    /// @notice Check whether a slot is currently occupied.
    /// @param slotId  The slot to check.
    /// @return True if a token is equipped in the slot.
    function isSlotOccupied(bytes32 slotId) external view returns (bool);
}
