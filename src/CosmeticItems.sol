// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CosmeticItems is ERC1155, Ownable {
    mapping(uint256 => string) private _itemNames;
    mapping(uint256 => uint256) public maxSupply;
    mapping(uint256 => uint256) public totalMinted;

    error SupplyExceeded(uint256 itemId);

    constructor() ERC1155("") Ownable(msg.sender) {}

    function registerItem(uint256 itemId, string calldata name, uint256 cap) external onlyOwner {
        _itemNames[itemId] = name;
        if (cap > 0) maxSupply[itemId] = cap;
    }

    function mint(address to, uint256 itemId, uint256 amount) external onlyOwner {
        if (maxSupply[itemId] > 0 && totalMinted[itemId] + amount > maxSupply[itemId]) {
            revert SupplyExceeded(itemId);
        }
        totalMinted[itemId] += amount;
        _mint(to, itemId, amount, "");
    }

    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyOwner {
        for (uint256 i; i < ids.length; ++i) {
            if (maxSupply[ids[i]] > 0 && totalMinted[ids[i]] + amounts[i] > maxSupply[ids[i]]) {
                revert SupplyExceeded(ids[i]);
            }
            totalMinted[ids[i]] += amounts[i];
        }
        _mintBatch(to, ids, amounts, "");
    }

    function itemName(uint256 itemId) external view returns (string memory) {
        return _itemNames[itemId];
    }
}
