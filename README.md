# ERC-8216 Reference Implementation (v1.2)

A minimal, self-contained reference implementation of [ERC-8216 — Slot-Based Equipment for ERC-6551 Accounts](https://github.com/ethereum/ERCs/pull/1645). The contracts here demonstrate every requirement of the v1.2 amendment with the smallest production-shaped surface area that still passes the spec's full conformance bar.

**ERC-165 interface id:** `0xc1ef0b9e`

**Unequip disposition:** account-bound — assets remain in the TBA after a slot is cleared. Owner-bound is also conformant; the spec leaves disposition implementation-defined. See `EquippableAccount._unequip` for the inline pseudocode of the owner-bound alternative.

**Binding pattern:** bytecode-suffix, matching the spec's embedded reference. `(chainId, tokenContract, tokenId)` is read directly from the proxy's immutable runtime suffix via `extcodecopy` at offset `0x4d`. No storage slot, no initializer — see the contract NatSpec on `EquippableAccount`.

## What this repo demonstrates

- The full `IERC6551Equipment` v1.2 surface (13 functions, `SlotEntry` with cached `isERC721`)
- `equipAtMint` / `lockSlotAtMint` / `equipAndLockAtMint` parent-contract gating via `onlyParentContract`
- `equipFromBalance` reorganization flow under account-bound disposition
- The execute-layer two-stage integrity guard:
  - **Prefix** — refuse to dispatch any `execute()` whose `to` matches an equipped `tokenContract` (closes the approval-based bypass)
  - **Postfix** — verify each occupied slot's custody after the call returns (closes the direct-transfer bypass)
- Cached `isERC721` on every `SlotEntry` and exclusive use of the cached value in the postfix check (closes the type-shifting attack)
- `MAX_OCCUPIED_SLOTS = 64` per spec recommendation
- A parent-driven mint-time flow (`CharacterNFT.mintWithBoundEquipment`) that uses `equipAndLockAtMint` as the primary illustration

## Architecture

```
src/
├── interfaces/
│   ├── IERC6551.sol            — ERC-6551 Account / Executable / Registry interfaces
│   └── IERC6551Equipment.sol   — ERC-8216 v1.2 canonical interface (id 0xc1ef0b9e)
├── EquippableAccount.sol       — TBA implementation with equipment slots
├── ERC6551Registry.sol         — vendored canonical 6551 Registry (see deployment notes)
├── CharacterNFT.sol            — example parent NFT; demonstrates mint-time bound equipment
└── CosmeticItems.sol           — example ERC-1155 cosmetic supply

test/
└── Equipment.t.sol             — 61 tests covering the full v1.2 surface

script/
└── Deploy.s.sol                — Foundry deploy script
```

## Build & test

```sh
forge build
forge test
```

## Registry deployment notes

**The vendored `ERC6551Registry.sol` is for self-contained tests and pedagogy — it is not intended to be deployed to a public network.**

Production deployments SHOULD target the canonical 6551 singleton at `0x000000006551c19487814612e58FE06813775758`. Deploying the vendored copy and using it as a production Registry would fragment the canonical 6551 ecosystem — accounts produced by it would not interoperate with tooling, indexers, or marketplaces that expect the singleton's address-determinism.

**Address parity:** TBA proxies produced by this vendored Registry are byte-identical (runtime, storage layout, suffix offsets) to TBAs produced by the canonical singleton. Addresses computed against this vendored Registry differ from canonical-singleton TBAs **only in the deployer-address term of the CREATE2 hash** — bytecode is byte-identical, only the deployer differs. `EquippableAccount.token()`'s `extcodecopy` at offset `0x4d` works identically against both.

The vendored copy uses an `abi.encodePacked` construction of the init code rather than the canonical Registry's hand-rolled assembly. Both paths produce byte-identical init code and therefore byte-identical proxy runtime; the readable form trades a few hundred gas per `createAccount` for a substantially clearer audit surface, which is the right trade-off for a reference repo.

## v1.1 → v1.2 changes

This repo previously implemented the v1.1 interface (id `0xd38f0891`). The v1.2 amendment is purely additive on the function set, but ABI-breaking on `SlotEntry` and behaviour-altering on `unequip` disposition.

### New functions
- `equipAtMint(bytes32, address, uint256, uint256)` — parent-contract-gated, no transfer; balance-asserted
- `lockSlotAtMint(bytes32)` — parent-contract-gated lock
- `equipFromBalance(bytes32, address, uint256, uint256)` — owner-gated, no transfer; balance-asserted
- `equipAndLockAtMint(bytes32, address, uint256, uint256)` — parent-contract-gated combined operation; emits both `Equipped` and `SlotLocked`

### `SlotEntry` struct change (ABI-breaking)
Adds a 6th field `bool isERC721`, cached at equip time via ERC-165 probe and never re-probed thereafter. This altered the on-chain ABI shape of `getLoadout()`'s return type — old indexers will misread layouts produced by v1.2 implementations.

### ERC-165 interface id change
`0xd38f0891` → `0xc1ef0b9e`. The id change makes the interface shift detectable on-chain; `supportsInterface(0xd38f0891)` now returns `false`.

### Unequip disposition
v1.1 hardcoded transfer-to-caller. v1.2 leaves disposition implementation-defined; this repo demonstrates account-bound (asset retained in TBA). Implementations MUST document and consistently apply their disposition. The owner-bound alternative is shown inline in `EquippableAccount._unequip`'s NatSpec.

### Removed in this implementation
- `_isERC1155` internal helper — the cached-flag flow makes it unreachable; the v1.1 fallback to "neither 721 nor 1155 → revert" is gone
- `InvalidTokenType` error — the v1.2 flow probes once for `isERC721` at equip time and otherwise treats the token as ERC-1155; if the contract is neither, the subsequent `safeTransferFrom` call fails naturally with the contract's own revert. No external NatSpec or docs in this repo referenced these symbols, so they are removed without a backwards-compat shim.

### Other implementation changes
- Bytecode-suffix binding replaces stored-binding. `REGISTRY` immutable, `initialize()`, and the `_chainId / _tokenContract / _tokenId / _initialized` storage slots are gone. `token()` reads from `extcodecopy(address(), _, 0x4d, 0x60)`.
- `execute()` gains the prefix execute-target restriction.
- `MAX_OCCUPIED_SLOTS = 64` enforced in equip and equipFromBalance paths.

## Implementation notes

### Double-reservation across slots is documented behavior
The balance check in `equipAtMint`, `equipFromBalance`, and `equipAndLockAtMint` is a per-slot `>=` check, not a per-asset reserved-sum check. Two non-locked slots can each claim the same `(tokenContract, tokenId)` for `amount = 1` when the TBA holds 1 — each slot's local check passes, and the postfix integrity check re-validates each occupied slot's recorded amount independently. Locked slots are still unmodifiable; the prefix execute-target restriction still anchors the `tokenContract` regardless of how many slots reference it.

**Indexers, marketplaces, and frontends rendering "free balance" on a TBA MUST aggregate amounts across all occupied slots that point at the same `(tokenContract, tokenId)` and subtract that sum from the on-chain balance.** Implementations MAY add a per-asset reservation tracker if they wish to forbid double-reservation, but the spec does not require it and this reference impl does not add one.

### Ownership-loop guard (consideration for implementers)
ERC-6551 has a known concern: if NFT A's TBA holds NFT A itself, the ownership graph contains a cycle and `ownerOf` traversal can fail to resolve. ERC-8216 does not mandate a guard for this — the prefix execute-target restriction blocks the most direct exfiltration path, and the equipment interface is otherwise indifferent to the parent-NFT identity. Production implementations MAY want to reject equip operations where the equipped `(tokenContract, tokenId)` matches the `(tokenContract, tokenId)` returned by this account's `token()`. This reference repo does not add the guard so the demonstrated surface stays minimal and focused on the v1.2 amendment.

## Links

- Spec: [ERC-8216 v1.2 (PR #1645)](https://github.com/ethereum/ERCs/pull/1645)
- Discussion: [Ethereum Magicians thread](https://ethereum-magicians.org/t/erc-8216-slot-based-equipment-for-erc-6551-token-bound-accounts/28139)
- ERC-6551 reference: [erc6551/reference](https://github.com/erc6551/reference)

## License

CC0-1.0
