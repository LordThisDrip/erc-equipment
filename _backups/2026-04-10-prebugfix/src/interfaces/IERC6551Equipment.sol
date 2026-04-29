// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IERC6551Equipment — Slot-Based Equipment for Token Bound Accounts
/// @notice A standard interface for equipping, unequipping, and permanently
///         locking tokens within ERC-6551 Token Bound Accounts using named slots.
/// @dev    Slots are identified by bytes32 keys, allowing any application to
///         define its own slot taxonomy. The recommended convention is
///         keccak256("slot.<name>"). Applications sharing a TBA across contexts
///         SHOULD namespace slots to avoid collisions, e.g.
///         keccak256("myapp.slot.head") vs keccak256("otherapp.slot.head").
///
///         Slots may be permanently locked, making them immutable across
///         ownership transfers. Locked means locked forever — there is no
///         unlock mechanism by design.
///
///         The ERC-165 identifier for this interface is 0xd38f0891.

interface IERC6551Equipment {

    /// @notice Metadata describing an occupied equipment slot.
    struct SlotEntry {
        bytes32 slotId;
        address tokenContract;
        uint256 tokenId;
        uint256 amount;
        bool locked;
    }

    event Equipped(
        bytes32 indexed slotId,
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 amount
    );

    event Unequipped(
        bytes32 indexed slotId,
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 amount
    );

    event SlotLocked(
        bytes32 indexed slotId,
        address indexed tokenContract,
        uint256 tokenId
    );

    function equip(bytes32 slotId, address tokenContract, uint256 tokenId, uint256 amount) external;

    function unequip(bytes32 slotId) external;

    function lockSlot(bytes32 slotId) external;

    function equipBatch(
        bytes32[] calldata slotIds,
        address[] calldata tokenContracts,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external;

    function lockSlots(bytes32[] calldata slotIds) external;

    function getEquipped(bytes32 slotId) external view returns (address tokenContract, uint256 tokenId, uint256 amount);

    function getLoadout() external view returns (SlotEntry[] memory entries);

    function isSlotOccupied(bytes32 slotId) external view returns (bool);

    function isSlotLocked(bytes32 slotId) external view returns (bool);
}
