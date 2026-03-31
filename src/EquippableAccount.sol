// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC6551Account, IERC6551Executable} from "./interfaces/IERC6551.sol";
import {IERC6551Equipment} from "./interfaces/IERC6551Equipment.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract EquippableAccount is
    IERC6551Account,
    IERC6551Executable,
    IERC6551Equipment,
    ERC1155Holder,
    ERC721Holder
{
    // ── Storage ──

    uint256 private _state;
    bool private _initialized;
    uint256 private _chainId;
    address private _tokenContract;
    uint256 private _tokenId;

    mapping(bytes32 => SlotEntry) private _slots;
    bytes32[] private _occupiedSlots;
    mapping(bytes32 => uint256) private _slotIndex;

    // ── Errors ──

    error NotAuthorized();
    error SlotAlreadyOccupied(bytes32 slotId);
    error SlotEmpty(bytes32 slotId);
    error SlotIsLocked(bytes32 slotId);
    error SlotAlreadyLocked(bytes32 slotId);
    error InvalidAmount();
    error ArrayLengthMismatch();
    error AlreadyInitialized();

    // ── Modifiers ──

    modifier onlyOwner() {
        if (!_isValidSigner(msg.sender)) revert NotAuthorized();
        _;
    }

    // ── Initializer ──

    function initialize(uint256 chainId_, address tokenContract_, uint256 tokenId_) external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        _chainId = chainId_;
        _tokenContract = tokenContract_;
        _tokenId = tokenId_;
    }

    // ── ERC-6551 Account ──

    receive() external payable override {}

    function token()
        public
        view
        override
        returns (uint256 chainId, address tokenContract, uint256 tokenId)
    {
        return (_chainId, _tokenContract, _tokenId);
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

    function execute(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) external payable override onlyOwner returns (bytes memory result) {
        require(operation == 0, "Only CALL supported");
        ++_state;

        bool success;
        (success, result) = to.call{value: value}(data);
        require(success, "Execution failed");
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
            interfaceId == type(IERC165).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ── Internal ──

    function _equip(
        bytes32 slotId,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    ) internal {
        if (_slots[slotId].locked) revert SlotIsLocked(slotId);
        if (_slotIndex[slotId] != 0) revert SlotAlreadyOccupied(slotId);
        if (amount == 0) revert InvalidAmount();

        if (amount == 1 && _isERC721(tokenContract)) {
            IERC721(tokenContract).safeTransferFrom(msg.sender, address(this), tokenId);
        } else {
            IERC1155(tokenContract).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        }

        _slots[slotId] = SlotEntry({
            slotId: slotId,
            tokenContract: tokenContract,
            tokenId: tokenId,
            amount: amount,
            locked: false
        });

        _occupiedSlots.push(slotId);
        _slotIndex[slotId] = _occupiedSlots.length;

        ++_state;

        emit Equipped(slotId, tokenContract, tokenId, amount);
    }

    function _unequip(bytes32 slotId) internal {
        if (_slots[slotId].locked) revert SlotIsLocked(slotId);

        uint256 idx = _slotIndex[slotId];
        if (idx == 0) revert SlotEmpty(slotId);

        SlotEntry memory entry = _slots[slotId];

        if (entry.amount == 1 && _isERC721(entry.tokenContract)) {
            IERC721(entry.tokenContract).safeTransferFrom(address(this), msg.sender, entry.tokenId);
        } else {
            IERC1155(entry.tokenContract).safeTransferFrom(
                address(this), msg.sender, entry.tokenId, entry.amount, ""
            );
        }

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

        emit Unequipped(slotId, entry.tokenContract, entry.tokenId, entry.amount);
    }

    function _lockSlot(bytes32 slotId) internal {
        if (_slotIndex[slotId] == 0) revert SlotEmpty(slotId);
        if (_slots[slotId].locked) revert SlotAlreadyLocked(slotId);

        _slots[slotId].locked = true;
        ++_state;

        SlotEntry memory entry = _slots[slotId];
        emit SlotLocked(slotId, entry.tokenContract, entry.tokenId);
    }

    function _isValidSigner(address signer) internal view returns (bool) {
        if (_chainId != block.chainid) return false;
        return IERC721(_tokenContract).ownerOf(_tokenId) == signer;
    }

    function _isERC721(address tokenContract) internal view returns (bool) {
        try IERC165(tokenContract).supportsInterface(type(IERC721).interfaceId) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }
}
