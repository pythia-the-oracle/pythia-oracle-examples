// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title IPythiaVisionRegistry
 * @notice Interface for Pythia Visions — AI market intelligence delivered on-chain.
 *
 * Visions are free. subscribe() registers your address to filter VisionFired events.
 * The events themselves are public — anyone can read them from the event log.
 *
 * PATTERN TYPES (BTC):
 *   0x11 = CAPITULATION_STRONG   85-87% bullish at 24h, avg +7-8%
 *   0x10 = CAPITULATION_BOUNCE   80% bullish at 24h, avg +5-7%
 *   0x21 = EMA_DIVERGENCE_STRONG 89% bullish at 24h, avg +6%
 *   0x20 = EMA_DIVERGENCE_SNAP   74-80% bullish at 24h, avg +4-5%
 *   0x30 = BOLLINGER_EXTREME     74% bullish at 24h, avg +3-4%
 *   0x40 = OVERBOUGHT_CONT      60-65% bullish at 24-48h
 *
 * DIRECTION:
 *   1 = BULLISH
 *
 * Docs: https://pythia.c3x-solutions.com
 */
interface IPythiaVisionRegistry {
    // ── Events ──

    /// @notice Emitted when AI detects a backtested pattern
    /// @param tokenId keccak256 of token name (e.g. keccak256("BTC"))
    /// @param patternType Pattern code (0x11 = CAPITULATION_STRONG, etc.)
    /// @param confidence AI-calibrated confidence (55-89), within pattern's accuracy range
    /// @param direction 1 = BULLISH
    /// @param price Token price at detection (18 decimals)
    /// @param payload ABI-encoded full Vision: indicators, analysis, feeds-to-watch
    event VisionFired(
        bytes32 indexed tokenId,
        uint8   patternType,
        uint8   confidence,
        uint8   direction,
        uint256 price,
        bytes   payload
    );

    /// @notice Emitted when an address subscribes to a token's Visions
    event Subscribed(address indexed subscriber, bytes32 indexed tokenId);

    /// @notice Emitted when an address unsubscribes
    event Unsubscribed(address indexed subscriber, bytes32 indexed tokenId);

    // ── Subscriber functions ──

    /// @notice Subscribe to Visions for a token. Free — no LINK required.
    function subscribe(bytes32 tokenId) external;

    /// @notice Unsubscribe from a token's Visions
    function unsubscribe(bytes32 tokenId) external;

    /// @notice Check if an address is subscribed to a token
    function isSubscribed(address subscriber, bytes32 tokenId) external view returns (bool);
}
