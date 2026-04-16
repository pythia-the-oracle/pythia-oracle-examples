/**
 * Pythia Oracle Examples — VisionVaultGuard Deployment
 *
 * Deploys VisionVaultGuard (AI market intelligence reactor) to Polygon mainnet.
 *
 * NOTE: Visions are currently mainnet-only. No testnet VisionRegistry exists.
 *       For local testing, use `npx hardhat test` which uses mock registries.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-visions.js --network polygon
 *
 * After deployment:
 *   1. Fund the contract with LINK (for Events subscriptions)
 *   2. Call subscribeToVisions() to register for BTC Visions
 *   3. Set up a relay bot to watch VisionFired events and call processVision()
 *   4. The contract auto-subscribes to confirmation Events and tracks state
 */
const hre = require("hardhat");

const CONFIG = {
  polygon: {
    link:            "0xb0897686c545045aFc77CF20eC7A532E3120E0F1", // ERC-677 LINK (use PegSwap if needed)
    eventRegistry:   "0x73686087d737833C5223948a027E13B608623e21",
    visionRegistry:  "0x39407eEc3BA80746BC6156eD924D16C2689533Ed",
    linkFaucet:      "https://pegswap.chain.link/ (convert bridged LINK to ERC-677)"
  }
};

async function main() {
  const network = hre.network.name;
  const cfg = CONFIG[network];
  if (!cfg) throw new Error(`VisionVaultGuard is mainnet-only. Use --network polygon.`);

  console.log(`\nDeploying VisionVaultGuard to ${network}...`);
  console.log(`  LINK:             ${cfg.link}`);
  console.log(`  EventRegistry:    ${cfg.eventRegistry}`);
  console.log(`  VisionRegistry:   ${cfg.visionRegistry}`);

  const VisionVaultGuard = await hre.ethers.getContractFactory("VisionVaultGuard");
  const contract = await VisionVaultGuard.deploy(cfg.link, cfg.eventRegistry, cfg.visionRegistry);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log(`\nVisionVaultGuard deployed to: ${address}`);
  console.log(`\nNext steps:`);
  console.log(`  1. Fund with LINK: ${cfg.linkFaucet}`);
  console.log(`  2. Call subscribeToVisions() to register for BTC Visions`);
  console.log(`  3. Set up relay bot to watch VisionFired events on VisionRegistry`);
  console.log(`  4. When a Vision fires, relay calls processVision() with pattern data`);
  console.log(`  5. Contract auto-subscribes to confirmation Events`);
  console.log(`  6. Query isActionReady() or getStatus() for current state`);
  console.log(`\nExplorer: https://polygonscan.com/address/${address}`);
}

main().catch((err) => { console.error(err); process.exit(1); });
