/**
 * Pythia Oracle Examples — Events Subscriber Deployment
 *
 * Deploys EventSubscriber (indicator alert subscriber) to Polygon Amoy or mainnet.
 *
 * Usage:
 *   npx hardhat run scripts/deploy-events.js --network amoy
 *   npx hardhat run scripts/deploy-events.js --network polygon
 *
 * After deployment:
 *   1. Fund the contract with LINK
 *   2. Call subscribe("pol_RSI_5M_14", 3, 1, 3000000000)  — RSI below 30 for 3 days
 *   3. Note the returned eventId
 *   4. Listen for PythiaEvent(eventId) on the registry contract
 */
const hre = require("hardhat");

const CONFIG = {
  amoy: {
    link:     "0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904",
    registry: "0x931Aa640d29E6C9D9fB3002749a52EC7fb277f9c",
    linkFaucet: "https://faucets.chain.link/polygon-amoy"
  },
  polygon: {
    link:     "0xb0897686c545045aFc77CF20eC7A532E3120E0F1", // ERC-677 LINK (use PegSwap if needed)
    registry: "0x73686087d737833C5223948a027E13B608623e21",
    linkFaucet: "https://pegswap.chain.link/ (convert bridged LINK to ERC-677)"
  }
};

async function main() {
  const network = hre.network.name;
  const cfg = CONFIG[network];
  if (!cfg) throw new Error(`Unknown network: ${network}. Use 'amoy' or 'polygon'.`);

  console.log(`\nDeploying EventSubscriber to ${network}...`);
  console.log(`  LINK:     ${cfg.link}`);
  console.log(`  Registry: ${cfg.registry}`);

  const EventSubscriber = await hre.ethers.getContractFactory("EventSubscriber");
  const contract = await EventSubscriber.deploy(cfg.link, cfg.registry);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log(`\nEventSubscriber deployed to: ${address}`);
  console.log(`\nNext steps:`);
  console.log(`  1. Fund with LINK: ${cfg.linkFaucet}`);
  console.log(`  2. Call subscribe("pol_RSI_5M_14", 3, 1, 3000000000)`);
  console.log(`     → condition 1 = BELOW, threshold = RSI 30 (8 decimals)`);
  console.log(`  3. Note eventId, listen for PythiaEvent(eventId) on registry`);
  console.log(`\nExplorer: https://${network === "amoy" ? "amoy.polygonscan" : "polygonscan"}.com/address/${address}`);
}

main().catch((err) => { console.error(err); process.exit(1); });
