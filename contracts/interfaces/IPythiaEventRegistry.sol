// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title IPythiaEventRegistry
 * @notice Minimal interface for subscribing to Pythia on-chain indicator alerts.
 *
 * REGISTRY ADDRESSES:
 *   Mainnet (Polygon):   0x73686087d737833C5223948a027E13B608623e21
 *   Testnet (Amoy):      0x931Aa640d29E6C9D9fB3002749a52EC7fb277f9c
 *
 * CONDITIONS:
 *   0 = ABOVE         (v1 — active)
 *   1 = BELOW         (v1 — active)
 *   2 = CROSSES_ABOVE (future — accepted, not yet processed)
 *   3 = CROSSES_BELOW (future — accepted, not yet processed)
 *
 * THRESHOLD SCALE: 8 decimal places (e.g. RSI 30 = 3000000000)
 *
 * Docs: https://pythia.c3x-solutions.com
 */
interface IPythiaEventRegistry {
    // ── Events ──

    /// @notice Emitted when a subscription's condition is met
    event PythiaEvent(uint256 indexed eventId, int256 value);

    /// @notice Emitted when a new subscription is created
    event SubscriptionCreated(
        uint256 indexed eventId,
        address indexed owner,
        bytes32 indexed feedId,
        uint8   condition,
        int256  threshold,
        uint64  expiresAt
    );

    /// @notice Emitted when a subscriber cancels
    event SubscriptionCancelled(uint256 indexed eventId, uint256 refund);

    // ── Subscriber functions ──

    /// @notice Subscribe to an indicator alert. Approve LINK spending first.
    /// @param feedName Human-readable feed name (e.g. "pol_RSI_5M_14")
    /// @param numDays  How many days to monitor (1-365)
    /// @param condition 0=ABOVE, 1=BELOW, 2=CROSSES_ABOVE, 3=CROSSES_BELOW
    /// @param threshold Scaled to 8 decimals (e.g. RSI 30 = 3000000000)
    /// @return eventId Your subscription ID — listen for PythiaEvent(eventId)
    function subscribe(
        string calldata feedName,
        uint16 numDays,
        uint8 condition,
        int256 threshold
    ) external returns (uint256 eventId);

    /// @notice Cancel your subscription. Remaining whole days refunded.
    function cancelSubscription(uint256 eventId) external;

    // ── View helpers ──

    /// @notice Check if a subscription is active and not expired
    function isActive(uint256 eventId) external view returns (bool);

    /// @notice Check if a condition type is currently processed by the matcher
    function isConditionActive(uint8 condition) external view returns (bool);

    /// @notice Get the cost for N days at current price
    function getCost(uint16 numDays) external view returns (uint256);
}
