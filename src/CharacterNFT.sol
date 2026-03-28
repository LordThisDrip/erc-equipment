// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC6551Registry} from "./interfaces/IERC6551.sol";

contract CharacterNFT is ERC721, Ownable {
    uint256 private _nextTokenId;

    IERC6551Registry public immutable registry;
    address public immutable accountImplementation;

    mapping(uint256 => address) public accountOf;

    event CharacterMinted(uint256 indexed tokenId, address indexed tba, address indexed to);

    constructor(
        address _registry,
        address _accountImplementation
    ) ERC721("RemiliaVillage Character", "RVCHAR") Ownable(msg.sender) {
        registry = IERC6551Registry(_registry);
        accountImplementation = _accountImplementation;
    }

    function mint(address to) external returns (uint256 tokenId, address tba) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);

        tba = registry.createAccount(
            accountImplementation,
            bytes32(0),
            block.chainid,
            address(this),
            tokenId
        );

        accountOf[tokenId] = tba;
        emit CharacterMinted(tokenId, tba, to);
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }
}
