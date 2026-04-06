// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@chainlink/contracts/src/v0.8/operatorforwarder/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

/**
 * @title RSITrigger
 * @notice Execute logic when RSI crosses a threshold — no off-chain bot needed.
 *
 * Pattern: Your contract requests RSI from Pythia. When the oracle fulfills,
 * the callback checks the value and executes your strategy logic directly.
 *
 * Example use cases:
 *   - Pause trading when RSI > 80 (overbought)
 *   - Enable buying when RSI < 25 (oversold)
 *   - Adjust vault risk parameters based on momentum
 *
 * DEPLOYMENT (Polygon mainnet):
 *   _link:   0xb0897686c545045aFc77CF20eC7A532E3120E0F1
 *   _oracle: 0xAA37710aF244514691629Aa15f4A5c271EaE6891
 *   _jobId:  0x8920841054eb4082b5910af84afa005e00000000000000000000000000000000
 *
 * Docs: https://pythia.c3x-solutions.com
 */
contract RSITrigger is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    // ── State ──────────────────────────────────────────────────────────────
    uint256 public lastRSI;          // Last RSI value (18 decimals, so 65.5 = 65.5e18)
    bool    public tradingPaused;    // Example flag — set true when overbought
    bool    public buyEnabled;       // Example flag — set true when oversold

    // Thresholds (18 decimals)
    uint256 public overboughtThreshold = 80e18;  // RSI > 80 → pause trading
    uint256 public oversoldThreshold   = 25e18;  // RSI < 25 → enable buying

    bytes32 private jobId;
    uint256 private fee;  // Check pythia.c3x-solutions.com for current rates

    event RSIUpdated(uint256 rsi, bool paused, bool buyEnabled);
    event ThresholdBreached(string condition, uint256 rsi);

    constructor(address _link, address _oracle, bytes32 _jobId, uint256 _fee) ConfirmedOwner(msg.sender) {
        _setChainlinkToken(_link);
        _setChainlinkOracle(_oracle);
        jobId = _jobId;
        fee = _fee;
    }

    /**
     * @notice Fetch latest RSI and trigger strategy logic on fulfillment.
     * @param token Token engine ID, e.g. "pol", "aave", "morpho"
     * @param timeframe "5M", "1H", "1D", or "1W"
     */
    function checkRSI(string memory token, string memory timeframe) external onlyOwner {
        string memory feed = string.concat(token, "_RSI_", timeframe, "_14");
        Chainlink.Request memory req = _buildChainlinkRequest(
            jobId, address(this), this.fulfillRSI.selector
        );
        req._add("feed", feed);
        _sendChainlinkRequest(req, fee);
    }

    /**
     * @notice Oracle callback — evaluates RSI and applies strategy logic.
     *         Replace the if/else blocks with your own strategy.
     */
    function fulfillRSI(bytes32 _requestId, uint256 _rsi)
        public
        recordChainlinkFulfillment(_requestId)
    {
        lastRSI = _rsi;

        if (_rsi > overboughtThreshold) {
            tradingPaused = true;
            buyEnabled    = false;
            emit ThresholdBreached("overbought", _rsi);
            // TODO: add your logic here — pause vault, reduce position, etc.
        } else if (_rsi < oversoldThreshold) {
            tradingPaused = false;
            buyEnabled    = true;
            emit ThresholdBreached("oversold", _rsi);
            // TODO: add your logic here — open position, increase allocation, etc.
        } else {
            tradingPaused = false;
            buyEnabled    = false;
        }

        emit RSIUpdated(_rsi, tradingPaused, buyEnabled);
    }

    // ── Config ─────────────────────────────────────────────────────────────

    function setThresholds(uint256 _overbought, uint256 _oversold) external onlyOwner {
        require(_overbought > _oversold, "Invalid thresholds");
        overboughtThreshold = _overbought;
        oversoldThreshold   = _oversold;
    }

    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(_chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Transfer failed");
    }
}
