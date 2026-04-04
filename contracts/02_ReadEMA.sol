// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@chainlink/contracts/src/v0.8/operatorforwarder/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

/**
 * @title ReadEMA
 * @notice Read on-chain EMA (or any single indicator) from Pythia using your own LINK.
 *         Discovery tier — check https://pythia.c3x-solutions.com for current pricing.
 *
 * DEPLOYMENT (Polygon mainnet):
 *   _link:   0xb0897686c545045aFc77CF20eC7A532E3120E0F1  (ERC-677 LINK — use PegSwap if needed)
 *   _oracle: 0xAA37710aF244514691629Aa15f4A5c271EaE6891
 *   _jobId:  0x8920841054eb4082b5910af84afa005e00000000000000000000000000000000
 *
 * DEPLOYMENT (Polygon Amoy testnet — deterministic mock data):
 *   _link:   0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904
 *   _oracle: 0x3b3aC62d73E537E3EF84D97aB5B84B51aF8dB316
 *   _jobId:  0xf3ca621227714f72a70eee65f9b01f3f00000000000000000000000000000000
 *
 * After deploying: fund the contract with LINK, then call requestFeed().
 *
 * All values use 18 decimal places:
 *   EMA of 2500.00  → lastValue = 2500000000000000000000
 *   RSI of 65.4     → lastValue =   65400000000000000000
 *   Volatility 2.5% → lastValue =   25000000000000000  (scaled differently)
 *
 * Docs: https://pythia.c3x-solutions.com
 */
contract ReadEMA is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    uint256 public lastValue;
    bytes32 public lastRequestId;
    string  public lastFeed;

    bytes32 private jobId;
    uint256 private fee;  // Set via constructor — check pythia.c3x-solutions.com for current rates

    event FeedRequested(bytes32 indexed requestId, string feed);
    event FeedFulfilled(bytes32 indexed requestId, uint256 value);

    constructor(address _link, address _oracle, bytes32 _jobId, uint256 _fee) ConfirmedOwner(msg.sender) {
        _setChainlinkToken(_link);
        _setChainlinkOracle(_oracle);
        jobId = _jobId;
        fee = _fee;
    }

    /**
     * @notice Request any single indicator. Fund this contract with LINK first.
     * @param feed Feed name, e.g.:
     *   "pol_EMA_5M_20"        — POL 20-period EMA on 5-minute candles
     *   "aave_RSI_1D_14"       — AAVE 14-period RSI daily
     *   "morpho_VWAP_24H"      — Morpho 24h VWAP
     *   "crv_BOLLINGER_UPPER_5M" — CRV upper Bollinger Band (5M)
     *   "bal_VOLATILITY_30D"   — BAL 30-day realized volatility
     */
    function requestFeed(string memory feed) external onlyOwner returns (bytes32) {
        Chainlink.Request memory req = _buildChainlinkRequest(
            jobId, address(this), this.fulfill.selector
        );
        req._add("feed", feed);
        bytes32 requestId = _sendChainlinkRequest(req, FEE);
        lastRequestId = requestId;
        lastFeed = feed;
        emit FeedRequested(requestId, feed);
        return requestId;
    }

    /// @notice Oracle callback — called by the Pythia Chainlink node
    function fulfill(bytes32 _requestId, uint256 _value)
        public
        recordChainlinkFulfillment(_requestId)
    {
        lastValue = _value;
        emit FeedFulfilled(_requestId, _value);
    }

    /// @notice Withdraw unused LINK from this contract
    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(_chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Transfer failed");
    }

    /// @notice Decode value to human-readable with 2 decimal places (off-chain helper)
    function decodeValue(uint256 raw) external pure returns (uint256 whole, uint256 decimals) {
        whole    = raw / 1e18;
        decimals = (raw % 1e18) / 1e16; // 2 decimal places
    }
}
