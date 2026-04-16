const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("VisionVaultGuard", function () {
  // State enum mirrors the contract
  const State = { IDLE: 0, ALERT: 1, WATCHING: 2, CONFIRMED: 3 };

  // Pattern types from btc_regime_v4
  const CAPITULATION_STRONG = 0x11;
  const CAPITULATION_BOUNCE = 0x10;
  const BOLLINGER_EXTREME = 0x30;

  // Conditions
  const ABOVE = 0;
  const BELOW = 1;

  async function deployFixture() {
    const [owner, relay, other] = await ethers.getSigners();

    // Deploy mock LINK token
    const MockLinkToken = await ethers.getContractFactory("MockLinkToken");
    const link = await MockLinkToken.deploy();

    // Deploy mock registries
    const MockEventRegistry = await ethers.getContractFactory("MockEventRegistry");
    const eventRegistry = await MockEventRegistry.deploy(await link.getAddress());

    const MockVisionRegistry = await ethers.getContractFactory("MockVisionRegistry");
    const visionRegistry = await MockVisionRegistry.deploy();

    // Deploy VisionVaultGuard
    const VisionVaultGuard = await ethers.getContractFactory("VisionVaultGuard");
    const guard = await VisionVaultGuard.deploy(
      await link.getAddress(),
      await eventRegistry.getAddress(),
      await visionRegistry.getAddress()
    );

    // Fund guard with 100 LINK
    const fundAmount = ethers.parseEther("100");
    await link.mint(await guard.getAddress(), fundAmount);

    // Build standard test feeds (mimics Vision payload feeds-to-watch)
    const feeds = [
      { feedName: "btc_RSI_1H_14",  condition: ABOVE, threshold: 3500000000n },  // RSI > 35
      { feedName: "btc_VWAP_24H",   condition: ABOVE, threshold: 72000_00000000n }, // VWAP reclaim
      { feedName: "btc_EMA_1H_20",  condition: ABOVE, threshold: 71500_00000000n }, // EMA reclaim
    ];
    const meanings = ["oversold_exit", "vwap_reclaim", "ema_reclaim"];

    const btcPrice = ethers.parseEther("68284"); // 18 decimals

    return {
      owner, relay, other,
      link, eventRegistry, visionRegistry, guard,
      fundAmount, feeds, meanings, btcPrice,
    };
  }

  // ── Setup ──

  describe("deployment", function () {
    it("should start in IDLE state", async function () {
      const { guard } = await loadFixture(deployFixture);
      expect(await guard.state()).to.equal(State.IDLE);
    });

    it("should subscribe to BTC Visions", async function () {
      const { guard, visionRegistry } = await loadFixture(deployFixture);

      await guard.subscribeToVisions();

      const btcHash = ethers.keccak256(ethers.toUtf8Bytes("BTC"));
      expect(await visionRegistry.isSubscribed(await guard.getAddress(), btcHash)).to.be.true;
    });
  });

  // ── Vision Processing ──

  describe("processVision", function () {
    it("should transition IDLE → WATCHING and subscribe to Events", async function () {
      const { guard, feeds, meanings, btcPrice, eventRegistry } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      // State should be WATCHING
      expect(await guard.state()).to.equal(State.WATCHING);

      // 3 Event subscriptions created
      const [, , , , , confirmedCount, totalFeeds] = await guard.getStatus();
      expect(totalFeeds).to.equal(3);
      expect(confirmedCount).to.equal(0);

      // All subscriptions active in registry
      for (let i = 1; i <= 3; i++) {
        expect(await eventRegistry.isActive(i)).to.be.true;
      }
    });

    it("should store Vision data correctly", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      const [state, patternType, confidence, direction, price] = await guard.getStatus();
      expect(patternType).to.equal(CAPITULATION_STRONG);
      expect(confidence).to.equal(86);
      expect(direction).to.equal(1);
      expect(price).to.equal(btcPrice);
    });

    it("should emit VisionProcessed event", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await expect(guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      ))
        .to.emit(guard, "VisionProcessed")
        .withArgs(CAPITULATION_STRONG, 86, btcPrice, 3);
    });

    it("should deduct LINK for Event subscriptions", async function () {
      const { guard, link, feeds, meanings, btcPrice, fundAmount } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      // 3 feeds × 7 days × 1 LINK/day = 21 LINK
      const expectedCost = ethers.parseEther("21");
      const balance = await link.balanceOf(await guard.getAddress());
      expect(balance).to.equal(fundAmount - expectedCost);
    });

    it("should store confirmation details", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      const [eventId0, feedName0, meaning0, fired0] = await guard.getConfirmation(0);
      expect(eventId0).to.equal(1);
      expect(feedName0).to.equal("btc_RSI_1H_14");
      expect(meaning0).to.equal("oversold_exit");
      expect(fired0).to.be.false;

      const [eventId2, feedName2, meaning2] = await guard.getConfirmation(2);
      expect(eventId2).to.equal(3);
      expect(feedName2).to.equal("btc_EMA_1H_20");
      expect(meaning2).to.equal("ema_reclaim");
    });

    it("should reject empty feeds", async function () {
      const { guard, btcPrice } = await loadFixture(deployFixture);

      await expect(guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, [], []
      )).to.be.revertedWith("no feeds");
    });

    it("should reject confidence out of range", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await expect(guard.processVision(
        CAPITULATION_STRONG, 30, 1, btcPrice, feeds, meanings
      )).to.be.revertedWith("confidence out of range");
    });

    it("should reject mismatched feeds/meanings arrays", async function () {
      const { guard, feeds, btcPrice } = await loadFixture(deployFixture);

      await expect(guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, ["only_one"]
      )).to.be.revertedWith("feeds/meanings length mismatch");
    });
  });

  // ── Deduplication ──

  describe("deduplication", function () {
    it("should reject same pattern within cooldown", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      await expect(guard.processVision(
        CAPITULATION_STRONG, 84, 1, btcPrice, feeds, meanings
      )).to.be.revertedWith("same pattern within cooldown");
    });

    it("should allow different pattern type immediately", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      // Different pattern — should work
      const bollingerFeeds = [
        { feedName: "btc_RSI_1H_14", condition: ABOVE, threshold: 4000000000n },
      ];
      await expect(guard.processVision(
        BOLLINGER_EXTREME, 70, 1, btcPrice, bollingerFeeds, ["not_deepening"]
      )).to.not.be.reverted;
    });
  });

  // ── Confirmation Flow ──

  describe("confirmations", function () {
    it("should track confirmation when Event fires", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      // RSI recovery fires (eventId = 1)
      const rsiValue = ethers.parseEther("38.2"); // 18 decimals
      await guard.reportConfirmation(1, rsiValue);

      const [, , , fired] = await guard.getConfirmation(0);
      expect(fired).to.be.true;

      // With requiredConfirmations = 1, state should be CONFIRMED
      expect(await guard.state()).to.equal(State.CONFIRMED);
    });

    it("should emit ConfirmationReceived and ActionReady", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      await expect(guard.reportConfirmation(1, ethers.parseEther("38.2")))
        .to.emit(guard, "ConfirmationReceived")
        .and.to.emit(guard, "ActionReady")
        .withArgs(CAPITULATION_STRONG, 86, 1);
    });

    it("should require multiple confirmations when configured", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.setRequiredConfirmations(2);
      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      // First confirmation — not enough
      await guard.reportConfirmation(1, ethers.parseEther("38.2"));
      expect(await guard.state()).to.equal(State.WATCHING);

      // Second confirmation — now CONFIRMED
      await guard.reportConfirmation(2, ethers.parseEther("72500"));
      expect(await guard.state()).to.equal(State.CONFIRMED);
    });

    it("should reject confirmation when not in WATCHING state", async function () {
      const { guard } = await loadFixture(deployFixture);

      await expect(guard.reportConfirmation(1, 100))
        .to.be.revertedWith("not watching");
    });

    it("should reject unknown eventId", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      await expect(guard.reportConfirmation(999, 100))
        .to.be.revertedWith("unknown or already fired eventId");
    });

    it("should reject duplicate confirmation", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.setRequiredConfirmations(3);
      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      await guard.reportConfirmation(1, ethers.parseEther("38.2"));

      await expect(guard.reportConfirmation(1, ethers.parseEther("39.0")))
        .to.be.revertedWith("unknown or already fired eventId");
    });
  });

  // ── State Queries ──

  describe("isActionReady", function () {
    it("should return true when CONFIRMED", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );
      await guard.reportConfirmation(1, ethers.parseEther("38.2"));

      expect(await guard.isActionReady()).to.be.true;
    });

    it("should return false when IDLE", async function () {
      const { guard } = await loadFixture(deployFixture);
      expect(await guard.isActionReady()).to.be.false;
    });

    it("should return false when WATCHING", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );
      expect(await guard.isActionReady()).to.be.false;
    });
  });

  // ── Admin ──

  describe("admin", function () {
    it("should allow owner to reset", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );
      expect(await guard.state()).to.equal(State.WATCHING);

      await guard.reset();
      expect(await guard.state()).to.equal(State.IDLE);
    });

    it("should cancel active subscriptions on reset", async function () {
      const { guard, feeds, meanings, btcPrice, eventRegistry } = await loadFixture(deployFixture);

      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );

      // All 3 subscriptions active
      expect(await eventRegistry.isActive(1)).to.be.true;

      await guard.reset();

      // All cancelled
      expect(await eventRegistry.isActive(1)).to.be.false;
      expect(await eventRegistry.isActive(2)).to.be.false;
      expect(await eventRegistry.isActive(3)).to.be.false;
    });

    it("should reject non-owner calls", async function () {
      const { guard, other, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      await expect(
        guard.connect(other).processVision(
          CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
        )
      ).to.be.reverted;
    });

    it("should allow withdrawing LINK", async function () {
      const { guard, link, owner, fundAmount } = await loadFixture(deployFixture);

      await guard.withdrawLink();
      expect(await link.balanceOf(owner.address)).to.equal(fundAmount);
    });
  });

  // ── Full Loop ──

  describe("full loop: Vision → Events → Action", function () {
    it("should complete the entire flow", async function () {
      const { guard, feeds, meanings, btcPrice } = await loadFixture(deployFixture);

      // 1. Subscribe to Visions
      await guard.subscribeToVisions();

      // 2. Vision fires — process it
      await guard.processVision(
        CAPITULATION_STRONG, 86, 1, btcPrice, feeds, meanings
      );
      expect(await guard.state()).to.equal(State.WATCHING);
      expect(await guard.isActionReady()).to.be.false;

      // 3. First confirmation: RSI recovers above 35
      await guard.reportConfirmation(1, ethers.parseEther("38.2"));
      expect(await guard.state()).to.equal(State.CONFIRMED);
      expect(await guard.isActionReady()).to.be.true;

      // 4. External contract reads the state
      const [state, patternType, confidence, direction, price, confirmed, total] =
        await guard.getStatus();

      expect(state).to.equal(State.CONFIRMED);
      expect(patternType).to.equal(CAPITULATION_STRONG);
      expect(confidence).to.equal(86);
      expect(direction).to.equal(1); // BULLISH
      expect(price).to.equal(btcPrice);
      expect(confirmed).to.equal(1);
      expect(total).to.equal(3);
    });
  });
});
