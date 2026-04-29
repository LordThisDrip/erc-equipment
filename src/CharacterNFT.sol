// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC6551Registry} from "./interfaces/IERC6551.sol";
import {IERC6551Equipment} from "./interfaces/IERC6551Equipment.sol";

/// @title CharacterNFT — pedagogical parent contract for ERC-8216 demos
/// @notice An ERC-721 character that, on mint, deploys a Token Bound Account
///         and exposes two flows:
///           1. plain `mint(to)` — no founder pack
///           2. `mintWithBoundEquipment(...)` — mint-time character-binding
///              flow that demonstrates `equipAndLockAtMint`
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

    /// @notice Plain mint: produces a character + empty TBA.
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

    /// @notice Mint a character with a permanently-locked founder item already
    ///         seated in the bound slot.
    /// @dev    Demonstrates the parent-driven mint-time flow specified by
    ///         ERC-8216 v1.2. The flow is:
    ///
    ///           1. mint the parent NFT to `to`
    ///           2. deploy the deterministic-address TBA via the canonical
    ///              registry — the TBA's binding is (chainId, this, tokenId)
    ///           3. assume the founder item already lives in the TBA balance
    ///              (the TBA address is computable in advance via
    ///              `registry.account(...)`, so callers can mint or transfer
    ///              the founder item to the predicted address ahead of this
    ///              call)
    ///           4. atomically register the asset into `slotId` AND
    ///              permanently lock it via `equipAndLockAtMint`
    ///
    ///         Step 4 is the v1.2-specific call. It is equivalent to:
    ///
    ///             IERC6551Equipment(tba).equipAtMint(slotId, tokenContract, tokenId, 1);
    ///             IERC6551Equipment(tba).lockSlotAtMint(slotId);
    ///
    ///         The combined form produces identical observable state and
    ///         emits both `Equipped` and `SlotLocked` events (in that
    ///         order), while saving a call frame and re-validation of
    ///         occupancy and lock state.
    ///
    ///         Access on the TBA-side `equipAndLockAtMint` is gated to the
    ///         parent contract — i.e. `address(this)` from this function's
    ///         perspective — so this call is the only path that can reach
    ///         it without going through the NFT-owner gate.
    function mintWithBoundEquipment(
        address to,
        address founderToken,
        uint256 founderTokenId,
        bytes32 slotId
    ) external onlyOwner returns (uint256 tokenId, address tba) {
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

        IERC6551Equipment(tba).equipAndLockAtMint(slotId, founderToken, founderTokenId, 1);

        emit CharacterMinted(tokenId, tba, to);
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }
}
