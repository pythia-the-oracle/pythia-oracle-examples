// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/IPythiaEventRegistry.sol";

/**
 * @title MockEventRegistry
 * @notice Minimal mock implementing IPythiaEventRegistry for testing.
 *         Tracks subscriptions and allows cancellation. Uses a mock LINK
 *         token for transferFrom on subscribe.
 */
contract MockEventRegistry is IPythiaEventRegistry {
    struct Sub {
        address owner;
        bool active;
    }

    uint256 public nextEventId = 1;
    uint256 public pricePerDay = 1 ether; // 1 LINK/day
    mapping(uint256 => Sub) public subs;

    address public linkToken;

    constructor(address _link) {
        linkToken = _link;
    }

    function subscribe(
        string calldata /* feedName */,
        uint16 numDays,
        uint8 /* condition */,
        int256 /* threshold */
    ) external override returns (uint256 eventId) {
        uint256 cost = uint256(numDays) * pricePerDay;
        // Pull LINK from caller
        (bool ok, ) = linkToken.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender, address(this), cost
            )
        );
        require(ok, "LINK transfer failed");

        eventId = nextEventId++;
        subs[eventId] = Sub({owner: msg.sender, active: true});
    }

    function cancelSubscription(uint256 eventId) external override {
        require(subs[eventId].owner == msg.sender, "only owner");
        require(subs[eventId].active, "not active");
        subs[eventId].active = false;
        emit SubscriptionCancelled(eventId, 0);
    }

    function isActive(uint256 eventId) external view override returns (bool) {
        return subs[eventId].active;
    }

    function isConditionActive(uint8 condition) external pure override returns (bool) {
        return condition <= 1; // ABOVE and BELOW active
    }

    function getCost(uint16 numDays) external view override returns (uint256) {
        return uint256(numDays) * pricePerDay;
    }
}
