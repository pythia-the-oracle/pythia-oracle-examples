// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@chainlink/contracts/src/v0.8/operatorforwarder/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

/**
 * @title VolatilityGuard
 * @notice Vault guard that adjusts risk parameters based on on-chain volatility data.
 *
 * Pattern: Fetch 30-day realized volatility from Pythia. On fulfillment, update
 * your vault's max leverage, deposit cap, or fee tier automatically.
 *
 * Example: dHEDGE / Enzyme vault strategy that reduces leverage when vol > 5%.
 *
 * DEPLOYMENT (Polygon mainnet):
 *   _link:   0xb0897686c545045aFc77CF20eC7A532E3120E0F1
 *   _oracle: 0xAA37710aF244514691629Aa15f4A5c271EaE6891
 *   _jobId:  0x8920841054eb4082b5910af84afa005e00000000000000000000000000000000
 *
 * Docs: https://pythia.c3x-solutions.com
 */
contract VolatilityGuard is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    // ── State ──────────────────────────────────────────────────────────────

    // Volatility is stored as 18-decimal fraction: 5% = 50000000000000000 (0.05e18)
    uint256 public lastVolatility;
    uint256 public maxLeverage;      // e.g. 300 = 3x, 100 = 1x (no leverage)
    uint256 public depositCap;       // max deposit allowed in current vol regime

    // Volatility regime thresholds (18 decimals)
    uint256 public constant LOW_VOL    = 0.03e18;  // < 3%  → high leverage allowed
    uint256 public constant MEDIUM_VOL = 0.06e18;  // 3–6%  → medium leverage
    uint256 public constant HIGH_VOL   = 0.10e18;  // > 10% → no leverage, cap deposits

    bytes32 private jobId;
    uint256 private fee;  // Check pythia.c3x-solutions.com for current rates

    event VolatilityUpdated(uint256 vol, uint256 newMaxLeverage, uint256 newDepositCap);

    constructor(address _link, address _oracle, bytes32 _jobId, uint256 _fee) ConfirmedOwner(msg.sender) {
        _setChainlinkToken(_link);
        _setChainlinkOracle(_oracle);
        jobId    = _jobId;
        fee      = _fee;
        maxLeverage = 300;
        depositCap  = 100 ether;
    }

    /**
     * @notice Fetch 30-day volatility for a token and update vault risk params.
     * @param token Token engine ID, e.g. "pol", "aave", "morpho"
     */
    function updateVolatility(string memory token) external onlyOwner {
        string memory feed = string.concat(token, "_VOLATILITY_30D");
        Chainlink.Request memory req = _buildChainlinkRequest(
            jobId, address(this), this.fulfillVolatility.selector
        );
        req._add("feed", feed);
        _sendChainlinkRequest(req, fee);
    }

    /**
     * @notice Oracle callback — adjusts vault parameters based on volatility regime.
     *         Replace the risk tiers with your own strategy parameters.
     */
    function fulfillVolatility(bytes32 _requestId, uint256 _vol)
        public
        recordChainlinkFulfillment(_requestId)
    {
        lastVolatility = _vol;

        if (_vol < LOW_VOL) {
            // Low volatility: allow up to 3x leverage, full deposit capacity
            maxLeverage = 300;
            depositCap  = 100 ether;
        } else if (_vol < MEDIUM_VOL) {
            // Medium volatility: reduce to 2x leverage
            maxLeverage = 200;
            depositCap  = 50 ether;
        } else if (_vol < HIGH_VOL) {
            // High volatility: 1.5x leverage max
            maxLeverage = 150;
            depositCap  = 25 ether;
        } else {
            // Extreme volatility: no leverage, minimal deposits
            maxLeverage = 100;
            depositCap  = 5 ether;
        }

        emit VolatilityUpdated(_vol, maxLeverage, depositCap);
    }

    /// @notice Check if a deposit amount is within current cap
    function isDepositAllowed(uint256 amount) external view returns (bool) {
        return amount <= depositCap;
    }

    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(_chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Transfer failed");
    }
}
