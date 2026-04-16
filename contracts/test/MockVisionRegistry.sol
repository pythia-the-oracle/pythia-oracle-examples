// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/IPythiaVisionRegistry.sol";

/**
 * @title MockVisionRegistry
 * @notice Minimal mock for testing Vision subscribers.
 */
contract MockVisionRegistry is IPythiaVisionRegistry {
    mapping(address => mapping(bytes32 => bool)) public subscriptions;

    function subscribe(bytes32 tokenId) external override {
        subscriptions[msg.sender][tokenId] = true;
        emit Subscribed(msg.sender, tokenId);
    }

    function unsubscribe(bytes32 tokenId) external override {
        subscriptions[msg.sender][tokenId] = false;
        emit Unsubscribed(msg.sender, tokenId);
    }

    function isSubscribed(address subscriber, bytes32 tokenId) external view override returns (bool) {
        return subscriptions[subscriber][tokenId];
    }

    /// @notice Test helper: emit a VisionFired event for testing
    function mockFireVision(
        bytes32 tokenId,
        uint8 patternType,
        uint8 confidence,
        uint8 direction,
        uint256 price,
        bytes calldata payload
    ) external {
        emit VisionFired(tokenId, patternType, confidence, direction, price, payload);
    }
}
