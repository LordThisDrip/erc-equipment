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
        // Deploy infra
        registry = new ERC6551Registry();
        accountImpl = new EquippableAccount();
        character = new CharacterNFT(address(registry), address(accountImpl));
        cosmetics = new CosmeticItems();

        // Register items
        cosmetics.registerItem(ITEM_RED_HOODIE, "Red Hoodie", 100);
        cosmetics.registerItem(ITEM_GOLD_CHAIN, "Gold Chain", 50);
        cosmetics.registerItem(ITEM_KATANA, "Katana", 0);        // uncapped
        cosmetics.registerItem(ITEM_HALO, "Halo", 10);           // limited

        // Mint character to Alice → auto-deploys TBA
        vm.prank(alice);
        (charTokenId, tbaAddr) = character.mint(alice);

        // Give Alice some items
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

        // Approve TBA to pull cosmetics
        cosmetics.setApprovalForAll(tbaAddr, true);

        // Equip hoodie to body slot
        EquippableAccount(payable(tbaAddr)).equip(
            SLOT_BODY,
            address(cosmetics),
            ITEM_RED_HOODIE,
            1
        );

        // Verify slot is occupied
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_BODY));

        // Verify correct item
        (address tc, uint256 tid, uint256 amt) =
            EquippableAccount(payable(tbaAddr)).getEquipped(SLOT_BODY);
        assertEq(tc, address(cosmetics));
        assertEq(tid, ITEM_RED_HOODIE);
        assertEq(amt, 1);

        // Item moved from Alice to TBA
        assertEq(cosmetics.balanceOf(alice, ITEM_RED_HOODIE), 0);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);

        vm.stopPrank();
    }

    function test_UnequipReturnsItem() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(
            SLOT_WEAPON,
            address(cosmetics),
            ITEM_KATANA,
            1
        );

        // Unequip
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_WEAPON);

        // Slot is now empty
        assertFalse(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_WEAPON));

        // Item back with Alice
        assertEq(cosmetics.balanceOf(alice, ITEM_KATANA), 1);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_KATANA), 0);

        vm.stopPrank();
    }

    function test_FullLoadout() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        // Equip four items to four slots
        EquippableAccount(payable(tbaAddr)).equip(SLOT_HEAD, address(cosmetics), ITEM_HALO, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_ACCESSORY, address(cosmetics), ITEM_GOLD_CHAIN, 1);

        // Get full loadout
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

        // Mint another item and try to equip to same slot
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
            SLOT_HEAD,
            address(cosmetics),
            ITEM_HALO,
            1
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

        // Alice sells character to Bob
        character.transferFrom(alice, bob, charTokenId);
        vm.stopPrank();

        // Bob now controls the TBA (and the equipped items)
        vm.prank(bob);
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_BODY);

        // Item goes to Bob, not Alice
        assertEq(cosmetics.balanceOf(bob, ITEM_RED_HOODIE), 1);
        assertEq(cosmetics.balanceOf(alice, ITEM_RED_HOODIE), 0);
    }
}
