const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("EventSubscriber", function () {
  async function deployFixture() {
    const [owner, other] = await ethers.getSigners();

    // Deploy mock LINK token
    const MockLinkToken = await ethers.getContractFactory("MockLinkToken");
    const link = await MockLinkToken.deploy();

    // Deploy mock registry
    const MockEventRegistry = await ethers.getContractFactory("MockEventRegistry");
    const registry = await MockEventRegistry.deploy(await link.getAddress());

    // Deploy EventSubscriber
    const EventSubscriber = await ethers.getContractFactory("EventSubscriber");
    const subscriber = await EventSubscriber.deploy(
      await link.getAddress(),
      await registry.getAddress()
    );

    // Fund subscriber with 100 LINK
    const fundAmount = ethers.parseEther("100");
    await link.mint(await subscriber.getAddress(), fundAmount);

    return { owner, other, link, registry, subscriber, fundAmount };
  }

  describe("subscribe", function () {
    it("should subscribe and store eventId", async function () {
      const { subscriber, link, registry } = await loadFixture(deployFixture);

      const tx = await subscriber.subscribe("pol_RSI_5M_14", 3, 1, 3000000000n);
      const receipt = await tx.wait();

      // Check eventId was stored
      expect(await subscriber.lastEventId()).to.equal(1);

      // Check subscription is active in registry
      expect(await registry.isActive(1)).to.be.true;

      // Check LINK was transferred (3 days * 1 LINK = 3 LINK)
      const subscriberBalance = await link.balanceOf(await subscriber.getAddress());
      expect(subscriberBalance).to.equal(ethers.parseEther("97")); // 100 - 3
    });

    it("should emit Subscribed event", async function () {
      const { subscriber } = await loadFixture(deployFixture);

      await expect(subscriber.subscribe("pol_RSI_5M_14", 3, 1, 3000000000n))
        .to.emit(subscriber, "Subscribed")
        .withArgs(1, "pol_RSI_5M_14", 1, 3000000000n);
    });

    it("should reject non-owner", async function () {
      const { subscriber, other } = await loadFixture(deployFixture);

      await expect(
        subscriber.connect(other).subscribe("pol_RSI_5M_14", 3, 1, 3000000000n)
      ).to.be.revertedWith("Only callable by owner");
    });
  });

  describe("cancel", function () {
    it("should cancel an active subscription", async function () {
      const { subscriber, registry } = await loadFixture(deployFixture);

      await subscriber.subscribe("pol_RSI_5M_14", 3, 1, 3000000000n);
      expect(await registry.isActive(1)).to.be.true;

      await subscriber.cancel(1);
      expect(await registry.isActive(1)).to.be.false;
    });

    it("should emit Cancelled event", async function () {
      const { subscriber } = await loadFixture(deployFixture);

      await subscriber.subscribe("pol_RSI_5M_14", 3, 1, 3000000000n);

      await expect(subscriber.cancel(1))
        .to.emit(subscriber, "Cancelled")
        .withArgs(1);
    });

    it("should reject non-owner", async function () {
      const { subscriber, other } = await loadFixture(deployFixture);

      await subscriber.subscribe("pol_RSI_5M_14", 3, 1, 3000000000n);

      await expect(
        subscriber.connect(other).cancel(1)
      ).to.be.revertedWith("Only callable by owner");
    });
  });

  describe("isActive", function () {
    it("should return true for active subscription", async function () {
      const { subscriber } = await loadFixture(deployFixture);

      await subscriber.subscribe("pol_RSI_5M_14", 3, 1, 3000000000n);
      expect(await subscriber.isActive(1)).to.be.true;
    });

    it("should return false for cancelled subscription", async function () {
      const { subscriber } = await loadFixture(deployFixture);

      await subscriber.subscribe("pol_RSI_5M_14", 3, 1, 3000000000n);
      await subscriber.cancel(1);
      expect(await subscriber.isActive(1)).to.be.false;
    });

    it("should return false for non-existent subscription", async function () {
      const { subscriber } = await loadFixture(deployFixture);
      expect(await subscriber.isActive(999)).to.be.false;
    });
  });

  describe("withdrawLink", function () {
    it("should withdraw all LINK to owner", async function () {
      const { owner, subscriber, link, fundAmount } = await loadFixture(deployFixture);

      await subscriber.withdrawLink();

      expect(await link.balanceOf(await subscriber.getAddress())).to.equal(0);
      expect(await link.balanceOf(owner.address)).to.equal(fundAmount);
    });

    it("should reject non-owner", async function () {
      const { subscriber, other } = await loadFixture(deployFixture);

      await expect(
        subscriber.connect(other).withdrawLink()
      ).to.be.revertedWith("Only callable by owner");
    });
  });

  describe("setRegistry", function () {
    it("should update registry address", async function () {
      const { subscriber, other } = await loadFixture(deployFixture);

      await subscriber.setRegistry(other.address);
      expect(await subscriber.registry()).to.equal(other.address);
    });

    it("should reject non-owner", async function () {
      const { subscriber, other } = await loadFixture(deployFixture);

      await expect(
        subscriber.connect(other).setRegistry(other.address)
      ).to.be.revertedWith("Only callable by owner");
    });
  });
});
