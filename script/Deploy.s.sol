// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC6551Registry} from "../src/ERC6551Registry.sol";
import {EquippableAccount} from "../src/EquippableAccount.sol";
import {CharacterNFT} from "../src/CharacterNFT.sol";
import {CosmeticItems} from "../src/CosmeticItems.sol";

contract DeployEquipment is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        ERC6551Registry registry = new ERC6551Registry();
        console2.log("Registry:", address(registry));

        EquippableAccount accountImpl = new EquippableAccount();
        console2.log("Account Impl:", address(accountImpl));

        CharacterNFT character = new CharacterNFT(
            address(registry),
            address(accountImpl)
        );
        console2.log("CharacterNFT:", address(character));

        CosmeticItems cosmetics = new CosmeticItems();
        console2.log("CosmeticItems:", address(cosmetics));

        cosmetics.registerItem(1, "Red Hoodie", 100);
        cosmetics.registerItem(2, "Gold Chain", 50);
        cosmetics.registerItem(3, "Katana", 0);
        cosmetics.registerItem(4, "Halo", 10);

        vm.stopBroadcast();

        console2.log("\n--- Deployment Complete ---");
    }
}
