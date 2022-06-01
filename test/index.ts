import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import { ethers } from "hardhat";

const toWei = (num: BigNumber) => ethers.utils.parseEther(num.toString());
const fromWei = (num: BigNumber) => ethers.utils.formatEther(num)

describe("Vesting Token", function () {
  // contract
  let vestingToken: Contract;
  // test account
  let deployer: SignerWithAddress, addr1: SignerWithAddress, addr2: SignerWithAddress;
  // before
  beforeEach(async function () {
    const VestingContract = await ethers.getContractFactory("DMTToken");
    [deployer, addr1, addr2] = await ethers.getSigners();
    vestingToken = await VestingContract.deploy();
  })
  // test deployment
  describe("Deployment", function () {
    it("Should track name and symbol of the token collection", async function () {
      expect(await vestingToken.name()).to.equal("DMT");
      expect(await vestingToken.symbol()).to.equal("DMT");
      expect(await vestingToken.decimals()).to.equal(18);
    })
    it("Should track initial information of the owner", async function () {
      expect(await vestingToken.owner()).to.equal(deployer.address);
      expect(fromWei(await vestingToken.balanceOf(deployer.address))).to.equal('2000000000.0');
      expect(fromWei(await vestingToken.totalSupply())).to.equal('2000000000.0');
    })
  })
  // test vesting
  describe("Vesting Check", function () {
    beforeEach(async function () {
      await vestingToken.createVesting(addr1.address, ethers.utils.parseUnits("100000000", 18), 10, 50, 3, []);
    })
    describe("Create Vesting", function () {
      it("Should track Create Vesting information of the add1", async function () {
        expect(await vestingToken.availableBalanceOf(addr1.address)).to.equal(0);
        expect(fromWei(await vestingToken.unReleaseAmount(addr1.address))).to.equal('100000000.0');
      })
      it("Should fail Create Again of the add1", async function () {
        await expect(vestingToken.createVesting(addr1.address, ethers.utils.parseUnits("100000000", 18), 10, 50, 3, [])).to.be.revertedWith('contract already exists');
      })
      it("Should fail First receive amount of the add1", async function () {
        await expect(vestingToken.release(addr1.address)).to.be.revertedWith('vesting timing no start');
        expect(await vestingToken.availableBalanceOf(addr1.address)).to.equal(0);
        expect(fromWei(await vestingToken.unReleaseAmount(addr1.address))).to.equal('100000000.0');
      })
      it("Should fail get param of the add1", async function () {
        await expect(vestingToken.nowReleaseAllAmount(addr1.address)).to.be.revertedWith('vesting timing no start');
        await expect(vestingToken.nextReleaseTime(addr1.address)).to.be.revertedWith('vesting timing no start');
        await expect(vestingToken.endReleaseTime(addr1.address)).to.be.revertedWith('vesting timing no start');
      })
    })
    describe("First receive amount", function () {
      beforeEach(async function () {
        await vestingToken.startTiming(addr1.address);
      })
      it("Should updata now release all amount of the add1", async function () {
        expect(fromWei(await vestingToken.nowReleaseAllAmount(addr1.address))).to.equal('10000000.0');
      })
      it("Should updata available balance, when First receive amount of the add1", async function () {
        await vestingToken.connect(addr1).release(addr1.address);
        expect(fromWei(await vestingToken.availableBalanceOf(addr1.address))).to.equal('10000000.0');
        expect(fromWei(await vestingToken.unReleaseAmount(addr1.address))).to.equal('90000000.0');
      })
    })
  })
});
