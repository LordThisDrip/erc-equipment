// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC6551Equipment} from "../src/interfaces/IERC6551Equipment.sol";
import {ERC6551Registry} from "../src/ERC6551Registry.sol";
import {EquippableAccount} from "../src/EquippableAccount.sol";
import {CharacterNFT} from "../src/CharacterNFT.sol";
import {CosmeticItems} from "../src/CosmeticItems.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract EquipmentTest is Test {
    ERC6551Registry registry;
    EquippableAccount accountImpl;
    CharacterNFT character;
    CosmeticItems cosmetics;

    address alice = makeAddr("alice");

    bytes32 constant SLOT_HEAD      = keccak256("slot.head");
    bytes32 constant SLOT_BODY      = keccak256("slot.body");
    bytes32 constant SLOT_WEAPON    = keccak256("slot.weapon");
    bytes32 constant SLOT_ACCESSORY = keccak256("slot.accessory");

    uint256 constant ITEM_RED_HOODIE = 1;
    uint256 constant ITEM_GOLD_CHAIN = 2;
    uint256 constant ITEM_KATANA     = 3;
    uint256 constant ITEM_HALO       = 4;

    uint256 charTokenId;
    address tbaAddr;

    function setUp() public {
        registry = new ERC6551Registry();
        accountImpl = new EquippableAccount();
        character = new CharacterNFT(address(registry), address(accountImpl));
        cosmetics = new CosmeticItems();

        cosmetics.registerItem(ITEM_RED_HOODIE, "Red Hoodie", 100);
        cosmetics.registerItem(ITEM_GOLD_CHAIN, "Gold Chain", 50);
        cosmetics.registerItem(ITEM_KATANA, "Katana", 0);
        cosmetics.registerItem(ITEM_HALO, "Halo", 10);

        vm.prank(alice);
        (charTokenId, tbaAddr) = character.mint(alice);

        cosmetics.mint(alice, ITEM_RED_HOODIE, 1);
        cosmetics.mint(alice, ITEM_GOLD_CHAIN, 1);
        cosmetics.mint(alice, ITEM_KATANA, 1);
        cosmetics.mint(alice, ITEM_HALO, 1);
    }

    // ─────────────────────────────────────────────
    //  Core Flow
    // ─────────────────────────────────────────────

    function test_EquipSingleItem() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_BODY));

        (address tc, uint256 tid, uint256 amt) =
            EquippableAccount(payable(tbaAddr)).getEquipped(SLOT_BODY);
        assertEq(tc, address(cosmetics));
        assertEq(tid, ITEM_RED_HOODIE);
        assertEq(amt, 1);

        assertEq(cosmetics.balanceOf(alice, ITEM_RED_HOODIE), 0);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);

        vm.stopPrank();
    }

    /// @dev Account-bound disposition: unequip clears the slot but the asset
    ///      stays in the TBA balance — owner gets it back via equipFromBalance
    ///      or via execute() into a non-equipped path.
    function test_UnequipKeepsAssetInTBA() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_WEAPON);

        assertFalse(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_WEAPON));
        assertEq(cosmetics.balanceOf(alice, ITEM_KATANA), 0);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_KATANA), 1);

        vm.stopPrank();
    }

    function test_FullLoadout() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_ACCESSORY, address(cosmetics), ITEM_GOLD_CHAIN, 1);

        IERC6551Equipment.SlotEntry[] memory loadout =
            EquippableAccount(payable(tbaAddr)).getLoadout();

        assertEq(loadout.length, 4);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  Reverts
    // ─────────────────────────────────────────────

    function test_RevertEquipOccupiedSlot() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        vm.stopPrank();
        cosmetics.mint(alice, ITEM_RED_HOODIE, 1);
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotAlreadyOccupied.selector, SLOT_HEAD));
        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_RED_HOODIE, 1);

        vm.stopPrank();
    }

    function test_RevertUnequipEmptySlot() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotEmpty.selector, SLOT_HEAD));
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_HEAD);
    }

    function test_RevertNonOwnerEquip() public {
        address bob = makeAddr("bob");
        vm.startPrank(bob);

        vm.expectRevert(EquippableAccount.NotAuthorized.selector);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────

    function test_EmitsEquippedEvent() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        vm.expectEmit(true, true, true, true);
        emit IERC6551Equipment.Equipped(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        vm.stopPrank();
    }

    function test_EmitsUnequippedEvent() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);

        vm.expectEmit(true, true, true, true);
        emit IERC6551Equipment.Unequipped(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);

        EquippableAccount(payable(tbaAddr)).unequip(SLOT_WEAPON);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  Ownership Transfer (account-bound)
    // ─────────────────────────────────────────────

    function test_NewOwnerControlsLoadoutAccountBound() public {
        address bob = makeAddr("bob");

        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        character.transferFrom(alice, bob, charTokenId);
        vm.stopPrank();

        vm.prank(bob);
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_BODY);

        // Account-bound: hoodie stays in the TBA, neither alice nor bob receives it
        assertEq(cosmetics.balanceOf(bob, ITEM_RED_HOODIE), 0);
        assertEq(cosmetics.balanceOf(alice, ITEM_RED_HOODIE), 0);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);
    }

    // ─────────────────────────────────────────────
    //  Slot Locking
    // ─────────────────────────────────────────────

    function test_LockSlot() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_BODY));

        vm.stopPrank();
    }

    function test_RevertEquipLockedSlot() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotIsLocked.selector, SLOT_BODY));
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_BODY);

        vm.stopPrank();
    }

    function test_RevertUnequipLockedSlot() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_WEAPON);

        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotIsLocked.selector, SLOT_WEAPON));
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_WEAPON);

        vm.stopPrank();
    }

    function test_RevertLockEmptySlot() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotEmpty.selector, SLOT_HEAD));
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_HEAD);
    }

    function test_RevertDoubleLock() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotAlreadyLocked.selector, SLOT_BODY));
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        vm.stopPrank();
    }

    function test_RevertNonOwnerLock() public {
        address bob = makeAddr("bob");

        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(EquippableAccount.NotAuthorized.selector);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);
    }

    function test_TransferPreservesLock() public {
        address bob = makeAddr("bob");

        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        character.transferFrom(alice, bob, charTokenId);
        vm.stopPrank();

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_BODY));

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotIsLocked.selector, SLOT_BODY));
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_BODY);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);
    }

    function test_EmitsSlotLockedEvent() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        vm.expectEmit(true, true, false, true);
        emit IERC6551Equipment.SlotLocked(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE);

        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        vm.stopPrank();
    }

    function test_LoadoutIncludesLockStatus() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);

        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        IERC6551Equipment.SlotEntry[] memory loadout =
            EquippableAccount(payable(tbaAddr)).getLoadout();

        assertEq(loadout.length, 2);

        for (uint256 i; i < loadout.length; i++) {
            if (loadout[i].slotId == SLOT_BODY) {
                assertTrue(loadout[i].locked);
                assertEq(loadout[i].tokenId, ITEM_RED_HOODIE);
            } else if (loadout[i].slotId == SLOT_WEAPON) {
                assertFalse(loadout[i].locked);
                assertEq(loadout[i].tokenId, ITEM_KATANA);
            }
        }

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  Batch Operations
    // ─────────────────────────────────────────────

    function test_EquipBatch() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        bytes32[] memory slotIds = new bytes32[](4);
        slotIds[0] = SLOT_HEAD;
        slotIds[1] = SLOT_BODY;
        slotIds[2] = SLOT_WEAPON;
        slotIds[3] = SLOT_ACCESSORY;

        address[] memory tokens = new address[](4);
        tokens[0] = address(cosmetics);
        tokens[1] = address(cosmetics);
        tokens[2] = address(cosmetics);
        tokens[3] = address(cosmetics);

        uint256[] memory tokenIds = new uint256[](4);
        tokenIds[0] = ITEM_HALO;
        tokenIds[1] = ITEM_RED_HOODIE;
        tokenIds[2] = ITEM_KATANA;
        tokenIds[3] = ITEM_GOLD_CHAIN;

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        amounts[3] = 1;

        EquippableAccount(payable(tbaAddr)).equipBatch(slotIds, tokens, tokenIds, amounts);

        IERC6551Equipment.SlotEntry[] memory loadout =
            EquippableAccount(payable(tbaAddr)).getLoadout();
        assertEq(loadout.length, 4);

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_HEAD));
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_BODY));
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_WEAPON));
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_ACCESSORY));

        vm.stopPrank();
    }

    function test_LockSlotsBatch() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);

        bytes32[] memory toLock = new bytes32[](2);
        toLock[0] = SLOT_HEAD;
        toLock[1] = SLOT_BODY;

        EquippableAccount(payable(tbaAddr)).lockSlots(toLock);

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_HEAD));
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_BODY));
        assertFalse(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_WEAPON));

        vm.stopPrank();
    }

    function test_RevertBatchArrayMismatch() public {
        vm.startPrank(alice);

        bytes32[] memory slotIds = new bytes32[](2);
        slotIds[0] = SLOT_HEAD;
        slotIds[1] = SLOT_BODY;

        address[] memory tokens = new address[](1);
        tokens[0] = address(cosmetics);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = ITEM_HALO;
        tokenIds[1] = ITEM_RED_HOODIE;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.expectRevert(EquippableAccount.ArrayLengthMismatch.selector);
        EquippableAccount(payable(tbaAddr)).equipBatch(slotIds, tokens, tokenIds, amounts);

        vm.stopPrank();
    }

    function test_BatchEquipAndLockMintFlow() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        bytes32[] memory slotIds = new bytes32[](4);
        slotIds[0] = SLOT_HEAD;
        slotIds[1] = SLOT_BODY;
        slotIds[2] = SLOT_WEAPON;
        slotIds[3] = SLOT_ACCESSORY;

        address[] memory tokens = new address[](4);
        tokens[0] = address(cosmetics);
        tokens[1] = address(cosmetics);
        tokens[2] = address(cosmetics);
        tokens[3] = address(cosmetics);

        uint256[] memory tokenIds = new uint256[](4);
        tokenIds[0] = ITEM_HALO;
        tokenIds[1] = ITEM_RED_HOODIE;
        tokenIds[2] = ITEM_KATANA;
        tokenIds[3] = ITEM_GOLD_CHAIN;

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        amounts[3] = 1;

        EquippableAccount(payable(tbaAddr)).equipBatch(slotIds, tokens, tokenIds, amounts);

        bytes32[] memory toLock = new bytes32[](2);
        toLock[0] = SLOT_HEAD;
        toLock[1] = SLOT_BODY;
        EquippableAccount(payable(tbaAddr)).lockSlots(toLock);

        IERC6551Equipment.SlotEntry[] memory loadout =
            EquippableAccount(payable(tbaAddr)).getLoadout();
        assertEq(loadout.length, 4);

        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotIsLocked.selector, SLOT_HEAD));
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_HEAD);

        EquippableAccount(payable(tbaAddr)).unequip(SLOT_WEAPON);
        assertFalse(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_WEAPON));

        vm.stopPrank();
    }

    function test_RevertBatchLockAlreadyLocked() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_HEAD);

        bytes32[] memory toLock = new bytes32[](2);
        toLock[0] = SLOT_HEAD;
        toLock[1] = SLOT_BODY;

        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotAlreadyLocked.selector, SLOT_HEAD));
        EquippableAccount(payable(tbaAddr)).lockSlots(toLock);

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  ERC-165 Support
    // ─────────────────────────────────────────────

    function test_SupportsEquipmentInterface() public view {
        assertTrue(
            EquippableAccount(payable(tbaAddr)).supportsInterface(type(IERC6551Equipment).interfaceId),
            "Must support IERC6551Equipment"
        );
    }

    function test_SupportsERC165() public view {
        assertTrue(
            EquippableAccount(payable(tbaAddr)).supportsInterface(type(IERC165).interfaceId),
            "Must support IERC165"
        );
    }

    function test_InterfaceIdMatchesSpec() public pure {
        assertEq(type(IERC6551Equipment).interfaceId, bytes4(0xc1ef0b9e));
    }

    /// @dev v1.1 → v1.2: the old interface ID must be reported as unsupported
    ///      so callers can detect the interface shift on-chain.
    function test_OldInterfaceIdRejected() public view {
        assertFalse(
            EquippableAccount(payable(tbaAddr)).supportsInterface(bytes4(0xd38f0891)),
            "Must NOT support the v1.1 interface id"
        );
    }

    // ─────────────────────────────────────────────
    //  CEI / state consistency
    // ─────────────────────────────────────────────

    function test_SlotOccupiedBeforeTransferCompletes() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_BODY));
        (address tc, uint256 tid, uint256 amt) =
            EquippableAccount(payable(tbaAddr)).getEquipped(SLOT_BODY);
        assertEq(tc, address(cosmetics));
        assertEq(tid, ITEM_RED_HOODIE);
        assertEq(amt, 1);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);

        vm.stopPrank();
    }

    function test_NewOwnerCanReorganizeUnlockedSlotsAfterTransfer() public {
        address bob = makeAddr("bob");

        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        character.transferFrom(alice, bob, charTokenId);
        vm.stopPrank();

        // Bob unequips weapon — katana stays in TBA (account-bound)
        vm.startPrank(bob);
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_WEAPON);
        assertEq(cosmetics.balanceOf(bob, ITEM_KATANA), 0);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_KATANA), 1);

        // Bob re-slots the same katana to the head slot via equipFromBalance
        EquippableAccount(payable(tbaAddr)).equipFromBalance(SLOT_HEAD, address(cosmetics), ITEM_KATANA, 1);
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_HEAD));

        // Body is still locked
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_BODY));

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  execute() — prefix restriction + postfix integrity
    // ─────────────────────────────────────────────

    function test_RevertExecuteIntoEquippedContract_LockedSlot() public {
        address attacker = makeAddr("attacker");
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        bytes memory transferData = abi.encodeWithSelector(
            IERC1155.safeTransferFrom.selector, tbaAddr, attacker, ITEM_RED_HOODIE, uint256(1), bytes("")
        );

        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.ExecuteIntoEquippedContract.selector, address(cosmetics))
        );
        EquippableAccount(payable(tbaAddr)).execute(address(cosmetics), 0, transferData, 0);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);
        assertEq(cosmetics.balanceOf(attacker, ITEM_RED_HOODIE), 0);
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_BODY));
        vm.stopPrank();
    }

    function test_RevertExecuteIntoEquippedContract_UnlockedSlot() public {
        address recipient = makeAddr("recipient");
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);

        bytes memory transferData = abi.encodeWithSelector(
            IERC1155.safeTransferFrom.selector, tbaAddr, recipient, ITEM_KATANA, uint256(1), bytes("")
        );

        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.ExecuteIntoEquippedContract.selector, address(cosmetics))
        );
        EquippableAccount(payable(tbaAddr)).execute(address(cosmetics), 0, transferData, 0);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_KATANA), 1);
        vm.stopPrank();
    }

    /// @dev Approval-based bypass: prefix must reject `setApprovalForAll` into
    ///      an equipped contract just like a direct transfer.
    function test_RevertExecuteSetApprovalForAllIntoEquippedContract() public {
        address attacker = makeAddr("attacker");
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        bytes memory approveData = abi.encodeWithSelector(
            IERC1155.setApprovalForAll.selector, attacker, true
        );

        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.ExecuteIntoEquippedContract.selector, address(cosmetics))
        );
        EquippableAccount(payable(tbaAddr)).execute(address(cosmetics), 0, approveData, 0);
        vm.stopPrank();
    }

    /// @dev Even a transfer of an UNEQUIPPED tokenId from an equipped contract
    ///      is blocked at prefix — the contract address itself is the anchor.
    function test_RevertExecutePrefixBlocksUnequippedTokenIdOnEquippedContract() public {
        // Equip red hoodie; put another item (gold chain) directly in the TBA
        cosmetics.mint(tbaAddr, ITEM_GOLD_CHAIN, 1);

        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        // Try to transfer the unequipped gold chain via execute() — prefix blocks
        // because the cosmetics contract is anchored by SLOT_BODY's hoodie.
        bytes memory transferData = abi.encodeWithSelector(
            IERC1155.safeTransferFrom.selector, tbaAddr, alice, ITEM_GOLD_CHAIN, uint256(1), bytes("")
        );

        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.ExecuteIntoEquippedContract.selector, address(cosmetics))
        );
        EquippableAccount(payable(tbaAddr)).execute(address(cosmetics), 0, transferData, 0);
        vm.stopPrank();
    }

    function test_ExecuteCanCallNonEquippedContract() public {
        // No equip happens — prefix loop is empty, postfix loop is empty.
        address recipient = makeAddr("recipient");
        cosmetics.mint(tbaAddr, ITEM_GOLD_CHAIN, 1);

        bytes memory transferData = abi.encodeWithSelector(
            IERC1155.safeTransferFrom.selector, tbaAddr, recipient, ITEM_GOLD_CHAIN, uint256(1), bytes("")
        );

        vm.prank(alice);
        EquippableAccount(payable(tbaAddr)).execute(address(cosmetics), 0, transferData, 0);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_GOLD_CHAIN), 0);
        assertEq(cosmetics.balanceOf(recipient, ITEM_GOLD_CHAIN), 1);
    }

    function test_RevertExecuteWithMultipleEquippedSlots() public {
        address attacker = makeAddr("attacker");
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);

        bytes memory transferData = abi.encodeWithSelector(
            IERC1155.safeTransferFrom.selector, tbaAddr, attacker, ITEM_KATANA, uint256(1), bytes("")
        );

        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.ExecuteIntoEquippedContract.selector, address(cosmetics))
        );
        EquippableAccount(payable(tbaAddr)).execute(address(cosmetics), 0, transferData, 0);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_HALO), 1);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_KATANA), 1);
        vm.stopPrank();
    }

    function test_RevertExecuteUnsupportedOperation() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.UnsupportedOperation.selector, uint8(1))
        );
        EquippableAccount(payable(tbaAddr)).execute(makeAddr("x"), 0, "", 1);
    }

    // ─────────────────────────────────────────────
    //  isERC721 cache + type-shifting defense
    // ─────────────────────────────────────────────

    function test_IsERC721CachedFor721() public {
        MockERC721 mock = new MockERC721();
        mock.mint(alice, 42);

        vm.startPrank(alice);
        mock.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(mock), 42, 1);

        IERC6551Equipment.SlotEntry[] memory loadout =
            EquippableAccount(payable(tbaAddr)).getLoadout();
        assertEq(loadout.length, 1);
        assertTrue(loadout[0].isERC721);
        vm.stopPrank();
    }

    function test_IsERC721CachedFor1155() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        IERC6551Equipment.SlotEntry[] memory loadout =
            EquippableAccount(payable(tbaAddr)).getLoadout();
        assertEq(loadout.length, 1);
        assertFalse(loadout[0].isERC721);
        vm.stopPrank();
    }

    /// @dev If the implementation re-probed ERC-165 instead of trusting the
    ///      cached `isERC721`, after `flip()` the postfix would call
    ///      IERC1155.balanceOf on a real 721 contract and either revert or
    ///      return 0, failing integrity. Test passing == cache respected.
    function test_TypeShiftingDefense_RespectsCachedFlag() public {
        MockShiftingToken shifty = new MockShiftingToken();
        shifty.mint(alice, 42);

        vm.startPrank(alice);
        shifty.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(shifty), 42, 1);

        IERC6551Equipment.SlotEntry[] memory loadout =
            EquippableAccount(payable(tbaAddr)).getLoadout();
        assertTrue(loadout[0].isERC721, "should cache 721 at equip");

        // Flip the token's ERC-165 response — it now denies being ERC-721.
        shifty.flip();
        assertFalse(shifty.supportsInterface(type(IERC721).interfaceId));

        // Trigger postfix via execute() into a non-equipped target. If cache
        // is respected, the integrity check goes through ownerOf and passes.
        address innocent = makeAddr("innocent");
        EquippableAccount(payable(tbaAddr)).execute(innocent, 0, "", 0);

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_HEAD));
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  Re-entrancy gating
    // ─────────────────────────────────────────────

    /// @dev A malicious ERC-1155 whose balanceOf re-enters the TBA must hit
    ///      the access-control gate — msg.sender during re-entry is the
    ///      token contract, not the NFT owner, so unequip/equip/lockSlot
    ///      revert NotAuthorized.
    function test_ReentrancyThroughIntegrityCheckIsGated() public {
        ReentrantToken rt = new ReentrantToken();
        rt.mint(alice, 1, 1);

        vm.startPrank(alice);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(rt), 1, 1);

        rt.arm(tbaAddr, SLOT_HEAD);

        // Trigger postfix via execute() into an EOA — postfix loops, calls
        // rt.balanceOf, which re-enters unequip(). Re-entry msg.sender == rt,
        // not alice → NotAuthorized bubbles all the way up and aborts execute.
        address innocent = makeAddr("innocent");
        vm.expectRevert(EquippableAccount.NotAuthorized.selector);
        EquippableAccount(payable(tbaAddr)).execute(innocent, 0, "", 0);

        // Slot remains intact — re-entry was blocked.
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_HEAD));
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  equipAtMint
    // ─────────────────────────────────────────────

    function test_EquipAtMint_OnlyParent() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 1);

        vm.prank(alice);
        vm.expectRevert(EquippableAccount.OnlyParentContract.selector);
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        address bob = makeAddr("bob");
        vm.prank(bob);
        vm.expectRevert(EquippableAccount.OnlyParentContract.selector);
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        vm.prank(address(character));
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_HEAD));
    }

    function test_EquipAtMint_NoTransferOccurs() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 1);

        uint256 tbaBalBefore = cosmetics.balanceOf(tbaAddr, ITEM_HALO);
        uint256 charBalBefore = cosmetics.balanceOf(address(character), ITEM_HALO);

        vm.prank(address(character));
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_HALO), tbaBalBefore);
        assertEq(cosmetics.balanceOf(address(character), ITEM_HALO), charBalBefore);
    }

    function test_EquipAtMint_RevertsInsufficientBalance_1155() public {
        // TBA holds nothing
        vm.prank(address(character));
        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.InsufficientTBABalance.selector, SLOT_HEAD)
        );
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
    }

    function test_EquipAtMint_RevertsInsufficientBalance_721() public {
        MockERC721 mock = new MockERC721();
        mock.mint(alice, 7); // owned by alice, not the TBA

        vm.prank(address(character));
        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.InsufficientTBABalance.selector, SLOT_HEAD)
        );
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(mock), 7, 1);
    }

    function test_EquipAtMint_RevertsOccupied() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 2);

        vm.prank(address(character));
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        vm.prank(address(character));
        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.SlotAlreadyOccupied.selector, SLOT_HEAD)
        );
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
    }

    function test_EquipAtMint_RevertsLocked() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 1);

        vm.prank(address(character));
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
        vm.prank(address(character));
        EquippableAccount(payable(tbaAddr)).lockSlotAtMint(SLOT_HEAD);

        // Even after the slot is freed (it can't be — locked is permanent), an
        // attempt to equip into a locked slot reverts SlotIsLocked.
        cosmetics.mint(tbaAddr, ITEM_RED_HOODIE, 1);
        vm.prank(address(character));
        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotIsLocked.selector, SLOT_HEAD));
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_RED_HOODIE, 1);
    }

    function test_EquipAtMint_ERC721Path() public {
        MockERC721 mock = new MockERC721();
        mock.mint(tbaAddr, 1);

        vm.prank(address(character));
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(mock), 1, 1);

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_HEAD));
        IERC6551Equipment.SlotEntry[] memory loadout =
            EquippableAccount(payable(tbaAddr)).getLoadout();
        assertTrue(loadout[0].isERC721);
        assertEq(mock.ownerOf(1), tbaAddr); // unchanged — no transfer
    }

    function test_EquipAtMint_RevertsZeroAmount() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 1);
        vm.prank(address(character));
        vm.expectRevert(EquippableAccount.InvalidAmount.selector);
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 0);
    }

    // ─────────────────────────────────────────────
    //  lockSlotAtMint
    // ─────────────────────────────────────────────

    function test_LockSlotAtMint_OnlyParent() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 1);
        vm.prank(address(character));
        EquippableAccount(payable(tbaAddr)).equipAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        vm.prank(alice);
        vm.expectRevert(EquippableAccount.OnlyParentContract.selector);
        EquippableAccount(payable(tbaAddr)).lockSlotAtMint(SLOT_HEAD);

        vm.prank(address(character));
        EquippableAccount(payable(tbaAddr)).lockSlotAtMint(SLOT_HEAD);
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_HEAD));
    }

    // ─────────────────────────────────────────────
    //  equipFromBalance
    // ─────────────────────────────────────────────

    function test_EquipFromBalance_OnlyOwner() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 1);

        address bob = makeAddr("bob");
        vm.prank(bob);
        vm.expectRevert(EquippableAccount.NotAuthorized.selector);
        EquippableAccount(payable(tbaAddr)).equipFromBalance(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        vm.prank(alice);
        EquippableAccount(payable(tbaAddr)).equipFromBalance(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_HEAD));
    }

    function test_EquipFromBalance_NoTransferOccurs() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 1);

        uint256 tbaBalBefore = cosmetics.balanceOf(tbaAddr, ITEM_HALO);
        uint256 aliceBalBefore = cosmetics.balanceOf(alice, ITEM_HALO);

        vm.prank(alice);
        EquippableAccount(payable(tbaAddr)).equipFromBalance(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_HALO), tbaBalBefore);
        assertEq(cosmetics.balanceOf(alice, ITEM_HALO), aliceBalBefore);
    }

    function test_EquipFromBalance_RevertsInsufficientBalance() public {
        // TBA holds nothing
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.InsufficientTBABalance.selector, SLOT_HEAD)
        );
        EquippableAccount(payable(tbaAddr)).equipFromBalance(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
    }

    function test_EquipFromBalance_ReorganizationFromUnequippedAsset() public {
        // Equip via wallet flow, then unequip — asset stays in TBA (account-bound)
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_KATANA, 1);
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_BODY);

        // Owner re-slots the TBA-held katana into a different slot
        EquippableAccount(payable(tbaAddr)).equipFromBalance(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_WEAPON));
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_KATANA), 1);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  equipAndLockAtMint
    // ─────────────────────────────────────────────

    function test_EquipAndLockAtMint_OnlyParent() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 1);

        vm.prank(alice);
        vm.expectRevert(EquippableAccount.OnlyParentContract.selector);
        EquippableAccount(payable(tbaAddr)).equipAndLockAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
    }

    function test_EquipAndLockAtMint_AtomicStateAndEvents() public {
        cosmetics.mint(tbaAddr, ITEM_HALO, 1);

        vm.expectEmit(true, true, true, true);
        emit IERC6551Equipment.Equipped(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
        vm.expectEmit(true, true, false, true);
        emit IERC6551Equipment.SlotLocked(SLOT_HEAD, address(cosmetics), ITEM_HALO);

        vm.prank(address(character));
        EquippableAccount(payable(tbaAddr)).equipAndLockAtMint(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_HEAD));
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_HEAD));
    }

    // ─────────────────────────────────────────────
    //  MAX_OCCUPIED_SLOTS
    // ─────────────────────────────────────────────

    function test_MaxSlotsExceeded() public {
        // Mint enough fungibles to fill 65 slots with amount 1 each
        cosmetics.mint(alice, ITEM_KATANA, 65);

        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        for (uint256 i; i < 64; ++i) {
            bytes32 slotId = keccak256(abi.encode("slot.test", i));
            EquippableAccount(payable(tbaAddr)).equip(slotId, address(cosmetics), ITEM_KATANA, 1);
        }

        bytes32 overflowSlot = keccak256(abi.encode("slot.test", uint256(64)));
        vm.expectRevert(EquippableAccount.MaxSlotsExceeded.selector);
        EquippableAccount(payable(tbaAddr)).equip(overflowSlot, address(cosmetics), ITEM_KATANA, 1);

        vm.stopPrank();
    }

    function test_MaxOccupiedSlotsConstant() public view {
        assertEq(EquippableAccount(payable(tbaAddr)).MAX_OCCUPIED_SLOTS(), 64);
    }

    // ─────────────────────────────────────────────
    //  Bytecode-suffix binding
    // ─────────────────────────────────────────────

    function test_BytecodeSuffixBinding() public {
        address newAcct = registry.createAccount(
            address(accountImpl), bytes32(uint256(42)), block.chainid, address(character), charTokenId
        );
        (uint256 chainId, address tokenContract, uint256 tokenId) =
            EquippableAccount(payable(newAcct)).token();
        assertEq(chainId, block.chainid);
        assertEq(tokenContract, address(character));
        assertEq(tokenId, charTokenId);
    }

    // ─────────────────────────────────────────────
    //  ERC-721 amount validation
    // ─────────────────────────────────────────────

    function test_RevertEquipERC721WithAmountGreaterThanOne() public {
        MockERC721 mock = new MockERC721();
        mock.mint(alice, 1);
        vm.startPrank(alice);
        mock.setApprovalForAll(tbaAddr, true);
        vm.expectRevert(EquippableAccount.InvalidAmount.selector);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(mock), 1, 2);
        vm.stopPrank();
    }

    function test_EquipERC721Successfully() public {
        MockERC721 mock = new MockERC721();
        mock.mint(alice, 42);
        vm.startPrank(alice);
        mock.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(mock), 42, 1);
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_HEAD));
        assertEq(mock.ownerOf(42), tbaAddr);
        vm.stopPrank();
    }
}

// ─────────────────────────────────────────────────────────────
//  Test mocks
// ─────────────────────────────────────────────────────────────

contract MockERC721 is ERC721 {
    constructor() ERC721("Mock721", "MOCK") {}
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

/// @dev ERC-721 that flips its ERC-165 response on demand.
contract MockShiftingToken is ERC721 {
    bool public claimsERC721 = true;

    constructor() ERC721("Shift", "SHIFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function flip() external {
        claimsERC721 = !claimsERC721;
    }

    function supportsInterface(bytes4 id) public view override returns (bool) {
        if (id == type(IERC721).interfaceId) return claimsERC721;
        return super.supportsInterface(id);
    }
}

/// @dev Minimal ERC-1155-shaped contract whose balanceOf is non-view and
///      attempts to re-enter the equippable account. Selector compatibility
///      with IERC1155 is preserved; `balanceOf` is intentionally NOT view so
///      it can issue state-mutating calls during the postfix integrity check.
contract ReentrantToken {
    mapping(address => mapping(uint256 => uint256)) private bal;
    address public attackTarget;
    bytes32 public attackSlotId;
    bool public armed;

    function mint(address to, uint256 id, uint256 amount) external {
        bal[to][id] += amount;
    }

    function arm(address target, bytes32 slotId) external {
        attackTarget = target;
        attackSlotId = slotId;
        armed = true;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata
    ) external {
        bal[from][id] -= amount;
        bal[to][id] += amount;
    }

    function safeBatchTransferFrom(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external {}

    function setApprovalForAll(address, bool) external {}

    function isApprovedForAll(address, address) external pure returns (bool) {
        return true;
    }

    function balanceOfBatch(address[] calldata, uint256[] calldata)
        external
        pure
        returns (uint256[] memory)
    {
        return new uint256[](0);
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        // 0xd9b67a26 = type(IERC1155).interfaceId
        return id == 0xd9b67a26 || id == 0x01ffc9a7;
    }

    /// @dev STATICCALLed at runtime (the postfix integrity check goes
    ///      through `IERC1155.balanceOf`, which is declared view in the
    ///      interface — so Solidity emits STATICCALL). We attempt re-entry
    ///      into the TBA's `unequip`; the re-entry's msg.sender is this
    ///      contract, and `unequip`'s onlyOwner gate is view-only and fires
    ///      `NotAuthorized` before any SSTORE — so the access-control gate
    ///      catches the re-entry. We MUST NOT do any SSTORE in this branch,
    ///      since the static context would short-circuit with an empty
    ///      revert and mask what we're testing.
    function balanceOf(address account, uint256 id) external returns (uint256) {
        if (armed && attackTarget != address(0)) {
            EquippableAccount(payable(attackTarget)).unequip(attackSlotId);
        }
        return bal[account][id];
    }
}
