// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC6551Equipment} from "../src/interfaces/IERC6551Equipment.sol";
import {ERC6551Registry} from "../src/ERC6551Registry.sol";
import {EquippableAccount} from "../src/EquippableAccount.sol";
import {CharacterNFT} from "../src/CharacterNFT.sol";
import {CosmeticItems} from "../src/CosmeticItems.sol";

contract EquipmentTest is Test {
    // ── Contracts ──
    ERC6551Registry registry;
    EquippableAccount accountImpl;
    CharacterNFT character;
    CosmeticItems cosmetics;

    // ── Actors ──
    address alice = makeAddr("alice");

    // ── Slot IDs ──
    bytes32 constant SLOT_HEAD      = keccak256("slot.head");
    bytes32 constant SLOT_BODY      = keccak256("slot.body");
    bytes32 constant SLOT_WEAPON    = keccak256("slot.weapon");
    bytes32 constant SLOT_ACCESSORY = keccak256("slot.accessory");

    // ── Item IDs ──
    uint256 constant ITEM_RED_HOODIE = 1;
    uint256 constant ITEM_GOLD_CHAIN = 2;
    uint256 constant ITEM_KATANA     = 3;
    uint256 constant ITEM_HALO       = 4;

    // ── State ──
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

        EquippableAccount(payable(tbaAddr)).equip(
            SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1
        );

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

    function test_UnequipReturnsItem() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(
            SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1
        );

        EquippableAccount(payable(tbaAddr)).unequip(SLOT_WEAPON);

        assertFalse(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_WEAPON));
        assertEq(cosmetics.balanceOf(alice, ITEM_KATANA), 1);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_KATANA), 0);

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
    //  Edge Cases / Reverts
    // ─────────────────────────────────────────────

    function test_RevertEquipOccupiedSlot() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);

        vm.stopPrank();
        cosmetics.mint(alice, ITEM_RED_HOODIE, 1);
        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.SlotAlreadyOccupied.selector, SLOT_HEAD)
        );
        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_RED_HOODIE, 1);

        vm.stopPrank();
    }

    function test_RevertUnequipEmptySlot() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.SlotEmpty.selector, SLOT_HEAD)
        );
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_HEAD);
    }

    function test_RevertNonOwnerEquip() public {
        address bob = makeAddr("bob");
        vm.startPrank(bob);

        vm.expectRevert(EquippableAccount.NotAuthorized.selector);
        EquippableAccount(payable(tbaAddr)).equip(
            SLOT_HEAD, address(cosmetics), ITEM_HALO, 1
        );

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
    //  Character Ownership Transfer
    // ─────────────────────────────────────────────

    function test_NewOwnerControlsLoadout() public {
        address bob = makeAddr("bob");

        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        character.transferFrom(alice, bob, charTokenId);
        vm.stopPrank();

        vm.prank(bob);
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_BODY);

        assertEq(cosmetics.balanceOf(bob, ITEM_RED_HOODIE), 1);
        assertEq(cosmetics.balanceOf(alice, ITEM_RED_HOODIE), 0);
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

        // Unequip should fail
        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.SlotIsLocked.selector, SLOT_BODY)
        );
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_BODY);

        vm.stopPrank();
    }

    function test_RevertUnequipLockedSlot() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_WEAPON);

        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.SlotIsLocked.selector, SLOT_WEAPON)
        );
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_WEAPON);

        vm.stopPrank();
    }

    function test_RevertLockEmptySlot() public {
        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.SlotEmpty.selector, SLOT_HEAD)
        );
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_HEAD);
    }

    function test_RevertDoubleLock() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.SlotAlreadyLocked.selector, SLOT_BODY)
        );
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

        // Transfer character to Bob
        character.transferFrom(alice, bob, charTokenId);
        vm.stopPrank();

        // Bob now owns the character but locked slot remains locked
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_BODY));

        // Bob cannot unequip the locked slot
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(EquippableAccount.SlotIsLocked.selector, SLOT_BODY)
        );
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_BODY);

        // Item stays in the TBA
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
}
