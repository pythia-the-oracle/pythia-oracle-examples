# Pythia Oracle — Integration Examples

**On-chain EMA, RSI, VWAP, Bollinger Bands, volatility, Events, and Visions via Chainlink.**
The only oracle delivering pre-calculated technical indicators and AI market intelligence for smart contracts.

→ Website: [pythia.c3x-solutions.com](https://pythia.c3x-solutions.com)
→ Twitter: [@pythia_oracle](https://x.com/pythia_oracle)
→ Telegram: [t.me/pythia_the_oracle](https://t.me/pythia_the_oracle)
→ MCP server: `pip install pythia-oracle-mcp`

---

## What Is Pythia?

Every other oracle provides raw prices. Pythia provides **calculated indicators**:

| Indicator | Description | Example Feed |
|-----------|-------------|-------------|
| EMA | Exponential Moving Average | `pol_EMA_5M_20` |
| RSI | Relative Strength Index (14-period) | `aave_RSI_1D_14` |
| VWAP | Volume-Weighted Average Price | `morpho_VWAP_24H` |
| Bollinger Bands | Upper/Lower bands | `crv_BOLLINGER_UPPER_5M` |
| Volatility | 30-day realized volatility | `bal_VOLATILITY_30D` |
| Liquidity Score | On-chain liquidity quality | `comp_LIQUIDITY_SCORE` |

**22 tokens** · **484 indicator instances** · **4 timeframes** (5M / 1H / 1D / 1W)
**Standard Chainlink interface** — works with any contract that uses `requestFeed` / `fulfill`

Plus **Events** (on-chain indicator alerts) and **Visions** (AI market intelligence — backtested patterns delivered on-chain for free).

---

## Quickstart — No LINK Needed

The Pythia Faucet is pre-funded and gives **5 free requests per address per day** on mainnet. No signup.

```solidity
// Just call the faucet — no LINK, no deployment
IPythiaFaucet faucet = IPythiaFaucet(0x640fC3B9B607E324D7A3d89Fcb62C77Cc0Bd420A);
faucet.requestIndicator("pol_RSI_1D_14");
// ~30 seconds later:
uint256 rsi = faucet.lastValue(); // e.g. 65400000000000000000 = RSI 65.4
```

→ Full example: [`contracts/01_FaucetTest.sol`](contracts/01_FaucetTest.sol)

---

## How to Read EMA On-Chain in 4 Lines of Solidity

```solidity
Chainlink.Request memory req = _buildChainlinkRequest(JOB_ID, address(this), this.fulfill.selector);
req._add("feed", "pol_EMA_5M_20");
_sendChainlinkRequest(req, fee); // fee set in constructor — check pythia.c3x-solutions.com
// oracle calls fulfill(requestId, value) ~30 seconds later
```

Full contract: [`contracts/02_ReadEMA.sol`](contracts/02_ReadEMA.sol)

---

## Examples

### 1. [`01_FaucetTest.sol`](contracts/01_FaucetTest.sol) — Free testdrive
No LINK required. Uses the pre-funded Pythia Faucet (5 req/day).
**Start here** to verify data before deploying your own consumer.

### 2. [`02_ReadEMA.sol`](contracts/02_ReadEMA.sol) — Read any single indicator
Minimal Discovery consumer. Deploy, fund with LINK, call `requestFeed()`.
Works on testnet (mock data) and mainnet (live data).

### 3. [`03_RSITrigger.sol`](contracts/03_RSITrigger.sol) — RSI-based strategy trigger
RSI crosses a threshold → your contract reacts. No off-chain bot needed.
**Use case:** pause trading when overbought, enable buying when oversold.

```solidity
// In fulfillment callback — no keeper, no cron job
if (rsi > OVERBOUGHT_THRESHOLD) {
    tradingPaused = true; // your vault pauses automatically
}
```

### 4. [`04_VolatilityGuard.sol`](contracts/04_VolatilityGuard.sol) — Volatility-aware vault
Adjust leverage limits and deposit caps based on live 30-day volatility.
**Use case:** dHEDGE / Enzyme vault that reduces risk in high-vol regimes automatically.

### 5. [`05_EventSubscriber.sol`](contracts/05_EventSubscriber.sol) — Events (indicator alerts)
Subscribe to on-chain indicator alerts. One-shot subscriptions: fires once when condition is met, unused whole days refunded in LINK.
**Use case:** get alerted when RSI drops below 30, when EMA crosses a level — no polling, no keeper.

```solidity
// Subscribe: "notify me when POL RSI drops below 30" for 7 days
subscriber.subscribe("pol_RSI_5M_14", 7, 1, 3000000000);
// condition 1 = BELOW, threshold = RSI 30 (8 decimal places)
// Listen for PythiaEvent(eventId) on the registry contract
```

### 6. [`06_VisionVaultGuard.sol`](contracts/06_VisionVaultGuard.sol) — Visions (AI market intelligence)
Automated risk layer that reacts to Pythia Visions — AI-detected market patterns delivered on-chain.
**Use case:** Pythia AI detects a BTC capitulation pattern (85-87% historically bullish), your vault automatically subscribes to confirmation Events and transitions through a state machine: `IDLE → WATCHING → CONFIRMED`.

```solidity
// 1. Subscribe to BTC Visions (free, one-time setup)
guard.subscribeToVisions();

// 2. When Pythia AI fires a Vision, relay bot calls processVision()
//    → Contract auto-subscribes to confirmation Events (paid LINK)

// 3. Query the state from your vault/strategy
if (guard.isActionReady()) {
    // A Vision has been confirmed by on-chain indicators
    (,uint8 patternType, uint8 confidence, uint8 direction,,,) = guard.getStatus();
    // e.g. patternType=0x11 (CAPITULATION_STRONG), confidence=87, direction=1 (BULLISH)
}
```

**BTC Pattern Types:**
| Code | Pattern | Historical Accuracy | Avg Move |
|------|---------|-------------------|----------|
| `0x11` | Capitulation Strong | 85-87% bullish | +7-8% |
| `0x10` | Capitulation Bounce | 80% bullish | +5-7% |
| `0x21` | EMA Divergence Strong | 89% bullish | +6% |
| `0x20` | EMA Divergence Snap | 74-80% bullish | +4-5% |
| `0x30` | Bollinger Extreme | 74% bullish | +3-4% |
| `0x40` | Overbought Continuation | 60-65% bullish | 24-48h |

---

## Network Configuration

### Polygon Amoy Testnet (free)
```
LINK Token:  0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904
Oracle:      0x3b3aC62d73E537E3EF84D97aB5B84B51aF8dB316
Job ID:      0xf3ca621227714f72a70eee65f9b01f3f00000000000000000000000000000000
LINK Faucet: https://faucets.chain.link/polygon-amoy
```
Testnet returns **deterministic mock values** so your integration tests are reproducible:
- Price feeds → `42000e18`
- RSI → `55.5e18`
- EMA → `41500e18`
- Volatility → `0.025e18` (2.5%)

### Polygon Mainnet
```
LINK Token:  0xb0897686c545045aFc77CF20eC7A532E3120E0F1  ← ERC-677 only!
Oracle:      0xAA37710aF244514691629Aa15f4A5c271EaE6891
Job ID:      0x8920841054eb4082b5910af84afa005e00000000000000000000000000000000
Faucet:      0x640fC3B9B607E324D7A3d89Fcb62C77Cc0Bd420A  (free, 5 req/day)
```

> ⚠️ **LINK token warning:** Polygon has two LINK tokens. Always use the ERC-677 version (`0xb089...`). If you have bridged ERC-20 LINK (`0x53e0...`), convert it at [pegswap.chain.link](https://pegswap.chain.link/) first.

### Deployed Consumer Contracts (Mainnet — use directly)

> **Current pricing:** Check [pythia.c3x-solutions.com](https://pythia.c3x-solutions.com) or use the [MCP server](https://pypi.org/project/pythia-oracle-mcp/) `get_pricing` tool for live rates.

| Tier | Address |
|------|---------|
| Discovery (any single indicator) | `0xeC2865d66ae6Af47926B02edd942A756b394F820` |
| Analysis (1H/1D/1W bundle) | `0x3b3aC62d73E537E3EF84D97aB5B84B51aF8dB316` |
| Speed (5M bundle) | `0xC406e7d9AC385e7AB43cBD56C74ad487f085d47B` |
| Complete (all indicators) | `0x2dEC98fd7173802b351d1E28d0Cd5DdD20C24252` |

### Event Registry (indicator alerts)

| Network | Address |
|---------|---------|
| Polygon Mainnet | `0x73686087d737833C5223948a027E13B608623e21` |
| Polygon Amoy | `0x931Aa640d29E6C9D9fB3002749a52EC7fb277f9c` |

Pricing: 1 LINK/day per subscription. Threshold: 8 decimal places (not 18 like regular feeds).

### Vision Registry (AI market intelligence)

| Network | Address |
|---------|---------|
| Polygon Mainnet | `0x39407eEc3BA80746BC6156eD924D16C2689533Ed` |

Subscription is **free**. Visions are currently mainnet-only.

---

## Feed Reference

### Tokens (engine IDs)
`pol` · `aave` · `morpho` · `crv` · `bal` · `comp` · `zro` · `w` · `quick` · `uniswap` · `wormhole` · `lido-dao` · `arpa`

### Feed Name Format
```
{engine_id}_{INDICATOR}_{TIMEFRAME}_{PARAM}

Examples:
  pol_USD_PRICE              — POL spot price
  pol_EMA_5M_20              — POL 20-period EMA on 5-min candles
  aave_RSI_1D_14             — AAVE 14-period RSI (daily)
  morpho_VWAP_24H            — Morpho 24h VWAP
  crv_BOLLINGER_UPPER_5M     — CRV upper Bollinger Band (5M)
  bal_BOLLINGER_LOWER_5M     — BAL lower Bollinger Band (5M)
  comp_VOLATILITY_30D        — COMP 30-day realized volatility
  zro_LIQUIDITY_SCORE        — ZRO liquidity quality score
```

### Timeframes
| Code | Period |
|------|--------|
| `5M` | 5 minutes |
| `1H` | 1 hour |
| `1D` | 1 day |
| `1W` | 1 week |

### Value Encoding
All values use **18 decimal places** (same as ETH/LINK):
```
RSI 65.4    → 65400000000000000000   (65.4 × 1e18)
EMA 2500.00 → 2500000000000000000000 (2500 × 1e18)
Vol 2.5%    →   25000000000000000    (0.025 × 1e18)
```

---

## Setup

```bash
git clone https://github.com/pythia-the-oracle/pythia-oracle-examples
cd pythia-oracle-examples
npm install
cp .env.example .env
# Edit .env with your RPC URL and private key
```

### Deploy to testnet
```bash
npx hardhat compile
npx hardhat run scripts/deploy.js --network amoy
```

### Deploy to mainnet
```bash
npx hardhat run scripts/deploy.js --network polygon
```

### Deploy Events subscriber
```bash
npx hardhat run scripts/deploy-events.js --network amoy     # testnet
npx hardhat run scripts/deploy-events.js --network polygon   # mainnet
```

### Deploy Visions vault guard (mainnet only)
```bash
npx hardhat run scripts/deploy-visions.js --network polygon
```

---

## Pricing Tiers

> **Live pricing:** [pythia.c3x-solutions.com](https://pythia.c3x-solutions.com) or MCP `get_pricing` tool. Fees may adjust with LINK price.

| Tier | What You Get |
|------|-------------|
| Discovery | Any single indicator (`uint256`) |
| Analysis | All 1H/1D/1W indicators bundled (`uint256[]`) |
| Speed | All 5M indicators bundled (`uint256[]`) |
| Complete | Everything bundled — cheapest per-indicator |

**Break-even:** Discovery becomes more expensive than Analysis after 3+ calls per token. Use Analysis/Complete for multi-indicator strategies.

---

## AI Agent Integration

If you're building an AI agent, trading bot, or using Claude/Cursor/any MCP-compatible client:

```bash
pip install pythia-oracle-mcp    # MCP server (Claude, Cursor, OpenAI, Windsurf)
pip install langchain-pythia     # LangChain tools (any LangChain/LangGraph agent)
```

Your AI agent can query live on-chain indicators, check oracle health, get contract addresses, and generate integration code — without writing Solidity.

- [MCP Server on PyPI](https://pypi.org/project/pythia-oracle-mcp/)
- [LangChain Integration on PyPI](https://pypi.org/project/langchain-pythia/)
- [Official MCP Registry](https://registry.modelcontextprotocol.io)

---

## Need Help?

- **Docs:** [pythia.c3x-solutions.com](https://pythia.c3x-solutions.com)
- **Twitter:** [@pythia_oracle](https://x.com/pythia_oracle)
- **Telegram:** [t.me/pythia_the_oracle](https://t.me/pythia_the_oracle)
- **Issues:** Open a GitHub issue in this repo

---

*Pythia is live on Polygon mainnet. Testnet (Amoy) always available for development.*
