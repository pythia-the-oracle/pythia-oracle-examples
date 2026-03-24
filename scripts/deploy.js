/**
 * Pythia Oracle Examples — Deployment Script
 *
 * Deploys ReadEMA (Discovery tier consumer) to Polygon Amoy testnet or mainnet.
 *
 * Usage:
 *   npx hardhat run scripts/deploy.js --network amoy
 *   npx hardhat run scripts/deploy.js --network polygon
 *
 * After deployment:
 *   1. Fund the contract with LINK
 *   2. Call requestFeed("pol_EMA_5M_20") from your wallet
 *   3. Wait ~30s for oracle fulfillment
 *   4. Read lastValue()
 */
const hre = require("hardhat");

const CONFIG = {
  amoy: {
    link:   "0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904",
    oracle: "0x3b3aC62d73E537E3EF84D97aB5B84B51aF8dB316",
    jobId:  "0xf3ca621227714f72a70eee65f9b01f3f00000000000000000000000000000000",
    linkFaucet: "https://faucets.chain.link/polygon-amoy"
  },
  polygon: {
    link:   "0xb0897686c545045aFc77CF20eC7A532E3120E0F1", // ERC-677 LINK (use PegSwap if needed)
    oracle: "0xAA37710aF244514691629Aa15f4A5c271EaE6891",
    jobId:  "0x8920841054eb4082b5910af84afa005e00000000000000000000000000000000",
    linkFaucet: "https://pegswap.chain.link/ (convert bridged LINK → ERC-677)"
  }
};

async function main() {
  const network = hre.network.name;
  const cfg = CONFIG[network];
  if (!cfg) throw new Error(`Unknown network: ${network}. Use 'amoy' or 'polygon'.`);

  console.log(`\nDeploying ReadEMA to ${network}...`);
  console.log(`  LINK:   ${cfg.link}`);
  console.log(`  Oracle: ${cfg.oracle}`);
  console.log(`  JobId:  ${cfg.jobId}`);

  const ReadEMA = await hre.ethers.getContractFactory("ReadEMA");
  const contract = await ReadEMA.deploy(cfg.link, cfg.oracle, cfg.jobId);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log(`\n✅ ReadEMA deployed to: ${address}`);
  console.log(`\nNext steps:`);
  console.log(`  1. Fund with LINK: ${cfg.linkFaucet}`);
  console.log(`  2. Call requestFeed("pol_EMA_5M_20")`);
  console.log(`  3. Wait ~30s, then read lastValue()`);
  console.log(`\nExplorer: https://${network === "amoy" ? "amoy.polygonscan" : "polygonscan"}.com/address/${address}`);
}

main().catch((err) => { console.error(err); process.exit(1); });
