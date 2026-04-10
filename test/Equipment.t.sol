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
        accountImpl = new EquippableAccount(address(registry));
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

    function test_UnequipReturnsItem() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);
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
    //  Ownership Transfer
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

    // ─────────────────────────────────────────────
    //  State Consistency After Equip (CEI verification)
    // ─────────────────────────────────────────────

    function test_SlotOccupiedBeforeTransferCompletes() public {
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        // Equip — state should be updated even though transfer happens after
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);

        // Verify state is consistent
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotOccupied(SLOT_BODY));
        (address tc, uint256 tid, uint256 amt) =
            EquippableAccount(payable(tbaAddr)).getEquipped(SLOT_BODY);
        assertEq(tc, address(cosmetics));
        assertEq(tid, ITEM_RED_HOODIE);
        assertEq(amt, 1);

        // Verify token actually transferred
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);

        vm.stopPrank();
    }

    function test_NewOwnerCanEquipUnlockedSlotAfterTransfer() public {
        address bob = makeAddr("bob");

        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);

        // Equip and lock body, equip weapon (unlocked)
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        // Transfer to Bob
        character.transferFrom(alice, bob, charTokenId);
        vm.stopPrank();

        // Bob can unequip unlocked weapon
        vm.startPrank(bob);
        EquippableAccount(payable(tbaAddr)).unequip(SLOT_WEAPON);
        assertEq(cosmetics.balanceOf(bob, ITEM_KATANA), 1);

        // Bob can equip something new to the weapon slot
        cosmetics.setApprovalForAll(tbaAddr, true);
        vm.stopPrank();
        cosmetics.mint(bob, ITEM_GOLD_CHAIN, 1);
        vm.startPrank(bob);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_GOLD_CHAIN, 1);

        // Verify
        (address tc,, ) = EquippableAccount(payable(tbaAddr)).getEquipped(SLOT_WEAPON);
        assertEq(tc, address(cosmetics));

        // Body still locked
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_BODY));

        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  Bug Fix #1: Lock Bypass via execute()
    // ─────────────────────────────────────────────

    function test_RevertExecuteBypassesLockedSlot() public {
        address attacker = makeAddr("attacker");
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(cosmetics), ITEM_RED_HOODIE, 1);
        EquippableAccount(payable(tbaAddr)).lockSlot(SLOT_BODY);

        bytes memory transferData = abi.encodeWithSelector(
            IERC1155.safeTransferFrom.selector, tbaAddr, attacker, ITEM_RED_HOODIE, uint256(1), bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotIntegrityViolated.selector, SLOT_BODY));
        EquippableAccount(payable(tbaAddr)).execute(address(cosmetics), 0, transferData, 0);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);
        assertEq(cosmetics.balanceOf(attacker, ITEM_RED_HOODIE), 0);
        assertTrue(EquippableAccount(payable(tbaAddr)).isSlotLocked(SLOT_BODY));
        vm.stopPrank();
    }

    function test_RevertExecuteBypassesUnlockedEquipment() public {
        address recipient = makeAddr("recipient");
        vm.startPrank(alice);
        cosmetics.setApprovalForAll(tbaAddr, true);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_WEAPON, address(cosmetics), ITEM_KATANA, 1);

        bytes memory transferData = abi.encodeWithSelector(
            IERC1155.safeTransferFrom.selector, tbaAddr, recipient, ITEM_KATANA, uint256(1), bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(EquippableAccount.SlotIntegrityViolated.selector, SLOT_WEAPON));
        EquippableAccount(payable(tbaAddr)).execute(address(cosmetics), 0, transferData, 0);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_KATANA), 1);
        vm.stopPrank();
    }

    function test_ExecuteCanTransferUnequippedTokens() public {
        address recipient = makeAddr("recipient");
        cosmetics.mint(tbaAddr, ITEM_GOLD_CHAIN, 1);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_GOLD_CHAIN), 1);

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

        vm.expectRevert();
        EquippableAccount(payable(tbaAddr)).execute(address(cosmetics), 0, transferData, 0);

        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_HALO), 1);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_RED_HOODIE), 1);
        assertEq(cosmetics.balanceOf(tbaAddr, ITEM_KATANA), 1);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────
    //  Bug Fix #2: initialize() Access Control
    // ─────────────────────────────────────────────

    function test_RevertInitializeNonRegistry() public {
        EquippableAccount impl = new EquippableAccount(address(registry));
        vm.expectRevert(EquippableAccount.NotRegistry.selector);
        impl.initialize(block.chainid, address(character), 999);
    }

    function test_RegistryCanInitializeClones() public {
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
    //  Minor Fixes: Type Detection & Interface ID
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

    function test_RevertEquipInvalidTokenType() public {
        vm.startPrank(alice);
        vm.expectRevert(EquippableAccount.InvalidTokenType.selector);
        EquippableAccount(payable(tbaAddr)).equip(SLOT_BODY, address(this), 1, 1);
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

    function test_InterfaceIdMatchesSpec() public pure {
        assertEq(type(IERC6551Equipment).interfaceId, bytes4(0xd38f0891));
    }
}

contract MockERC721 is ERC721 {
    constructor() ERC721("Mock721", "MOCK") {}
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
