// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "./interfaces/IPythiaEventRegistry.sol";

/**
 * @title EventSubscriber
 * @notice Subscribe to on-chain indicator alerts from Pythia. Get notified when
 *         RSI crosses a threshold, EMA drops below a level, etc. One-shot
 *         subscriptions that fire once and refund unused whole days.
 *
 * DEPLOYMENT (Polygon mainnet):
 *   _link:     0xb0897686c545045aFc77CF20eC7A532E3120E0F1  (ERC-677 LINK)
 *   _registry: 0x73686087d737833C5223948a027E13B608623e21
 *
 * DEPLOYMENT (Polygon Amoy testnet):
 *   _link:     0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904
 *   _registry: 0x931Aa640d29E6C9D9fB3002749a52EC7fb277f9c
 *
 * After deploying: fund with LINK, then call subscribe().
 *
 * THRESHOLD SCALING (8 decimal places — different from feed values which use 18):
 *   RSI 30       → threshold = 3000000000
 *   RSI 70       → threshold = 7000000000
 *   EMA $2500    → threshold = 250000000000   (2500 * 1e8)
 *   Volatility 5% → threshold = 500000000     (0.05 * 1e8)
 *
 * CONDITIONS:
 *   0 = ABOVE         (v1 — active)
 *   1 = BELOW         (v1 — active)
 *   2 = CROSSES_ABOVE (future — accepted, not yet processed)
 *   3 = CROSSES_BELOW (future — accepted, not yet processed)
 *
 * Docs: https://pythia.c3x-solutions.com
 */
contract EventSubscriber is ConfirmedOwner {
    LinkTokenInterface public immutable LINK;
    IPythiaEventRegistry public registry;

    uint256 public lastEventId;

    event Subscribed(uint256 indexed eventId, string feed, uint8 condition, int256 threshold);
    event Cancelled(uint256 indexed eventId);

    constructor(address _link, address _registry) ConfirmedOwner(msg.sender) {
        LINK = LinkTokenInterface(_link);
        registry = IPythiaEventRegistry(_registry);
    }

    /**
     * @notice Subscribe to an indicator alert. Fund this contract with LINK first.
     * @param feedName e.g. "pol_RSI_5M_14", "bitcoin_EMA_1H_20"
     * @param numDays  1-365 — how long to monitor
     * @param condition 0=ABOVE, 1=BELOW
     * @param threshold 8 decimals (e.g. RSI 30 = 3000000000)
     * @return eventId Listen for PythiaEvent(eventId) on the registry
     */
    function subscribe(
        string calldata feedName,
        uint16 numDays,
        uint8 condition,
        int256 threshold
    ) external onlyOwner returns (uint256 eventId) {
        uint256 cost = registry.getCost(numDays);
        LINK.approve(address(registry), cost);
        eventId = registry.subscribe(feedName, numDays, condition, threshold);
        lastEventId = eventId;
        emit Subscribed(eventId, feedName, condition, threshold);
    }

    /**
     * @notice Cancel a subscription. Remaining whole days refunded in LINK.
     * @param eventId The subscription ID returned by subscribe()
     */
    function cancel(uint256 eventId) external onlyOwner {
        registry.cancelSubscription(eventId);
        emit Cancelled(eventId);
    }

    /// @notice Check if a subscription is still active
    function isActive(uint256 eventId) external view returns (bool) {
        return registry.isActive(eventId);
    }

    /// @notice Update registry address (e.g. after upgrade)
    function setRegistry(address _registry) external onlyOwner {
        registry = IPythiaEventRegistry(_registry);
    }

    /// @notice Withdraw LINK from this contract
    function withdrawLink() external onlyOwner {
        LINK.transfer(msg.sender, LINK.balanceOf(address(this)));
    }
}
