// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "./interfaces/IPythiaEventRegistry.sol";
import "./interfaces/IPythiaVisionRegistry.sol";

/**
 * @title VisionVaultGuard
 * @notice Automated risk layer that reacts to Pythia Visions.
 *
 * HOW IT WORKS:
 *
 *   1. Pythia AI detects a BTC capitulation (85-87% historically bullish).
 *   2. A relay bot reads the VisionFired event and calls processVision().
 *   3. This contract reads the feeds-to-watch from the payload and
 *      auto-subscribes to those Pythia Events (e.g. "RSI crosses above 35").
 *   4. When the confirmation Events fire, the contract updates its state.
 *   5. Other contracts or bots read the state to make decisions.
 *
 * STATE MACHINE:
 *
 *   IDLE ──→ ALERT ──→ WATCHING ──→ CONFIRMED ──→ IDLE
 *           (vision)   (events      (enough        (auto-reset
 *            fires)     subscribed)  confirmations)  after cooldown)
 *
 * THE REVENUE LOOP (for context):
 *
 *   Vision (free) tells you WHAT happened + WHICH feeds to watch.
 *   Events (paid LINK) tell you WHEN the confirmation thresholds are hit.
 *   This contract automates the connection between the two.
 *
 * DEPLOYMENT (Polygon mainnet):
 *   _link:            0xb0897686c545045aFc77CF20eC7A532E3120E0F1
 *   _eventRegistry:   0x73686087d737833C5223948a027E13B608623e21
 *   _visionRegistry:  0x39407eEc3BA80746BC6156eD924D16C2689533Ed
 *
 * NOTE: Visions are currently mainnet-only. For local testing, use
 *       `npx hardhat test` which uses mock registries.
 *
 * After deploying: fund with LINK (for Events subscriptions), then
 * call subscribeToVisions(). A relay bot handles the rest.
 *
 * Docs: https://pythia.c3x-solutions.com
 */
contract VisionVaultGuard is ConfirmedOwner {

    // ── Types ──

    enum State { IDLE, ALERT, WATCHING, CONFIRMED }

    /// @notice A feed the Vision recommends watching for confirmation
    struct FeedWatch {
        string  feedName;       // e.g. "btc_RSI_1H_14"
        uint8   condition;      // 0=ABOVE, 1=BELOW
        int256  threshold;      // 8 decimals (Event Registry scale)
    }

    /// @notice Decoded Vision data relevant for on-chain decisions
    struct VisionData {
        uint8   patternType;    // 0x11=CAPITULATION_STRONG, etc.
        uint8   confidence;     // 55-89
        uint8   direction;      // 1=BULLISH
        uint256 price;          // 18 decimals
        uint64  receivedAt;     // block.timestamp when processVision was called
    }

    /// @notice Tracks a confirmation Event subscription
    struct Confirmation {
        uint256 eventId;        // PythiaEventRegistry subscription ID
        string  feedName;       // what feed we're watching
        string  meaning;        // "oversold_exit", "vwap_reclaim", etc.
        bool    fired;          // true once PythiaEvent(eventId) is detected
    }

    // ── Storage ──

    LinkTokenInterface      public immutable LINK;
    IPythiaEventRegistry    public eventRegistry;
    IPythiaVisionRegistry   public visionRegistry;

    bytes32 public constant BTC = keccak256("BTC");

    State       public state;
    VisionData  public lastVision;

    /// @notice Active confirmation subscriptions for the current Vision
    Confirmation[] public confirmations;

    /// @notice How many confirmations needed before state = CONFIRMED
    uint8 public requiredConfirmations = 1;

    /// @notice How many days to subscribe for confirmation Events
    uint16 public eventDays = 7;

    /// @notice Cooldown: minimum seconds between processing Visions (dedup)
    uint64 public visionCooldown = 24 hours;

    /// @notice Auto-reset to IDLE after this many seconds in CONFIRMED state
    uint64 public confirmedTimeout = 48 hours;

    /// @notice Count of confirmations received for current Vision
    uint8 public confirmationCount;

    // ── Events ──

    event VisionProcessed(uint8 patternType, uint8 confidence, uint256 price, uint8 feedCount);
    event ConfirmationSubscribed(uint256 indexed eventId, string feedName, string meaning);
    event ConfirmationReceived(uint256 indexed eventId, string feedName, int256 value);
    event StateChanged(State from, State to);
    event ActionReady(uint8 patternType, uint8 confidence, uint8 confirmationsReceived);

    // ── Constructor ──

    constructor(
        address _link,
        address _eventRegistry,
        address _visionRegistry
    ) ConfirmedOwner(msg.sender) {
        LINK = LinkTokenInterface(_link);
        eventRegistry = IPythiaEventRegistry(_eventRegistry);
        visionRegistry = IPythiaVisionRegistry(_visionRegistry);
        state = State.IDLE;
    }

    // ════════════════════════════════════════════════════════════════════
    //  STEP 1: Subscribe to BTC Visions (free, one-time setup)
    // ════════════════════════════════════════════════════════════════════

    /// @notice Register to receive BTC Visions. Call once after deployment.
    function subscribeToVisions() external onlyOwner {
        visionRegistry.subscribe(BTC);
    }

    // ════════════════════════════════════════════════════════════════════
    //  STEP 2: Relay bot calls this when VisionFired event is detected
    // ════════════════════════════════════════════════════════════════════

    /**
     * @notice Process a BTC Vision. Called by a relay bot (or Chainlink Automation)
     *         when it detects a VisionFired event from the PythiaVisionRegistry.
     *
     *         The bot decodes the VisionFired event off-chain and passes the
     *         structured data here. The contract does NOT trust the bot blindly —
     *         it checks cooldown and requires owner authorization for the relay.
     *
     * @param patternType  Pattern code from the Vision (0x11, 0x10, etc.)
     * @param confidence   AI-calibrated confidence (55-89)
     * @param direction    1=BULLISH
     * @param price        BTC price at detection (18 decimals)
     * @param feeds        Array of feeds to watch for confirmation
     * @param meanings     Array of meaning labels (same length as feeds)
     */
    function processVision(
        uint8 patternType,
        uint8 confidence,
        uint8 direction,
        uint256 price,
        FeedWatch[] calldata feeds,
        string[] calldata meanings
    ) external onlyOwner {
        require(feeds.length == meanings.length, "feeds/meanings length mismatch");
        require(feeds.length > 0, "no feeds");
        require(confidence >= 55 && confidence <= 100, "confidence out of range");

        // Dedup: don't process same pattern within cooldown
        if (state != State.IDLE) {
            // Allow override if it's a different pattern type
            require(
                patternType != lastVision.patternType ||
                block.timestamp >= lastVision.receivedAt + visionCooldown,
                "same pattern within cooldown"
            );
            // Clean up old subscriptions before starting new ones
            _cancelActiveSubscriptions();
        }

        // Store Vision data
        lastVision = VisionData({
            patternType: patternType,
            confidence:  confidence,
            direction:   direction,
            price:       price,
            receivedAt:  uint64(block.timestamp)
        });

        _setState(State.ALERT);

        // Subscribe to each recommended feed as a Pythia Event
        delete confirmations;
        confirmationCount = 0;

        for (uint256 i = 0; i < feeds.length; i++) {
            uint256 cost = eventRegistry.getCost(eventDays);
            require(LINK.balanceOf(address(this)) >= cost, "insufficient LINK");

            LINK.approve(address(eventRegistry), cost);
            uint256 eventId = eventRegistry.subscribe(
                feeds[i].feedName,
                eventDays,
                feeds[i].condition,
                feeds[i].threshold
            );

            confirmations.push(Confirmation({
                eventId:  eventId,
                feedName: feeds[i].feedName,
                meaning:  meanings[i],
                fired:    false
            }));

            emit ConfirmationSubscribed(eventId, feeds[i].feedName, meanings[i]);
        }

        _setState(State.WATCHING);
        emit VisionProcessed(patternType, confidence, price, uint8(feeds.length));
    }

    // ════════════════════════════════════════════════════════════════════
    //  STEP 3: Bot monitors PythiaEvent emissions, calls this on match
    // ════════════════════════════════════════════════════════════════════

    /**
     * @notice Report that a confirmation Event has fired. Called by the relay bot
     *         when it sees PythiaEvent(eventId) from the EventRegistry.
     *
     * @param eventId  The Event subscription ID that fired
     * @param value    The indicator value that triggered the Event (18 decimals)
     */
    function reportConfirmation(uint256 eventId, int256 value) external onlyOwner {
        require(state == State.WATCHING, "not watching");

        bool found = false;
        for (uint256 i = 0; i < confirmations.length; i++) {
            if (confirmations[i].eventId == eventId && !confirmations[i].fired) {
                confirmations[i].fired = true;
                confirmationCount++;
                found = true;
                emit ConfirmationReceived(eventId, confirmations[i].feedName, value);
                break;
            }
        }
        require(found, "unknown or already fired eventId");

        if (confirmationCount >= requiredConfirmations) {
            _setState(State.CONFIRMED);
            emit ActionReady(
                lastVision.patternType,
                lastVision.confidence,
                confirmationCount
            );
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  STEP 4: External contracts/bots read state and act
    // ════════════════════════════════════════════════════════════════════

    /// @notice Is there a confirmed, actionable Vision right now?
    function isActionReady() external view returns (bool) {
        if (state == State.CONFIRMED) {
            return block.timestamp < lastVision.receivedAt + confirmedTimeout;
        }
        return false;
    }

    /// @notice Full status for off-chain consumption
    function getStatus() external view returns (
        State   currentState,
        uint8   patternType,
        uint8   confidence,
        uint8   direction,
        uint256 price,
        uint8   confirmedCount,
        uint8   totalFeeds,
        uint64  visionTimestamp
    ) {
        return (
            _effectiveState(),
            lastVision.patternType,
            lastVision.confidence,
            lastVision.direction,
            lastVision.price,
            confirmationCount,
            uint8(confirmations.length),
            lastVision.receivedAt
        );
    }

    /// @notice Get a specific confirmation subscription's status
    function getConfirmation(uint256 index) external view returns (
        uint256 eventId,
        string memory feedName,
        string memory meaning,
        bool    fired
    ) {
        require(index < confirmations.length, "index out of bounds");
        Confirmation memory c = confirmations[index];
        return (c.eventId, c.feedName, c.meaning, c.fired);
    }

    /// @notice How many confirmation feeds are being watched
    function confirmationCount_() external view returns (uint256) {
        return confirmations.length;
    }

    // ════════════════════════════════════════════════════════════════════
    //  Admin
    // ════════════════════════════════════════════════════════════════════

    function setRequiredConfirmations(uint8 _count) external onlyOwner {
        require(_count > 0, "at least 1");
        requiredConfirmations = _count;
    }

    function setEventDays(uint16 _days) external onlyOwner {
        require(_days > 0 && _days <= 365, "1-365");
        eventDays = _days;
    }

    function setVisionCooldown(uint64 _seconds) external onlyOwner {
        visionCooldown = _seconds;
    }

    function setConfirmedTimeout(uint64 _seconds) external onlyOwner {
        confirmedTimeout = _seconds;
    }

    function setEventRegistry(address _registry) external onlyOwner {
        eventRegistry = IPythiaEventRegistry(_registry);
    }

    function setVisionRegistry(address _registry) external onlyOwner {
        visionRegistry = IPythiaVisionRegistry(_registry);
    }

    /// @notice Reset to IDLE manually. Cancels active Event subscriptions.
    function reset() external onlyOwner {
        _cancelActiveSubscriptions();
        _setState(State.IDLE);
    }

    /// @notice Withdraw LINK from this contract
    function withdrawLink() external onlyOwner {
        LINK.transfer(msg.sender, LINK.balanceOf(address(this)));
    }

    // ════════════════════════════════════════════════════════════════════
    //  Internal
    // ════════════════════════════════════════════════════════════════════

    function _effectiveState() internal view returns (State) {
        // Auto-expire CONFIRMED state after timeout
        if (state == State.CONFIRMED &&
            block.timestamp >= lastVision.receivedAt + confirmedTimeout) {
            return State.IDLE;
        }
        return state;
    }

    function _setState(State newState) internal {
        State old = state;
        state = newState;
        if (old != newState) {
            emit StateChanged(old, newState);
        }
    }

    function _cancelActiveSubscriptions() internal {
        for (uint256 i = 0; i < confirmations.length; i++) {
            if (!confirmations[i].fired) {
                // Try to cancel — may fail if already expired, that's ok
                try eventRegistry.cancelSubscription(confirmations[i].eventId) {}
                catch {}
            }
        }
    }
}
