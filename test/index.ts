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
    const add1Amount: BigNumber = ethers.utils.parseUnits("100000000", 18);
    it("Should fail if no owner", async function () {
      await expect(vestingToken.connect(addr1).createVesting(addr1.address, 0, 10, 50, 3, [])).to.be.revertedWith('Ownable: caller is not the owner');
      await expect(vestingToken.connect(addr1).startTiming(addr1.address)).to.be.revertedWith('Ownable: caller is not the owner');
    })
    it("Should fail if Create Vesting error param", async function () {
      await expect(vestingToken.createVesting(addr1.address, 0, 10, 50, 3, [])).to.be.revertedWith('Amount count is 0');
      await expect(vestingToken.createVesting(addr1.address, add1Amount, 10, 50, 0, [])).to.be.revertedWith('Release count is 0');
      await expect(vestingToken.createVesting(addr1.address, add1Amount, 101, 50, 3, [])).to.be.revertedWith('No more than one hundred');
      await expect(vestingToken.createVesting(addr1.address, add1Amount, 10, 50, 3, [10, 50, 20, 20])).to.be.revertedWith('Unlock time need correspond');
      await expect(vestingToken.createVesting(addr1.address, add1Amount, 10, 50, 3, [10, 50, 40])).to.be.revertedWith('The Ratio total is not 100');
      await expect(vestingToken.createVesting(addr1.address, add1Amount, 10, 50, 3, [10, 10, 10])).to.be.revertedWith('The Ratio total is not 100');
    })
    it("Should track Create Vesting emit of the add1", async function () {
      await expect(vestingToken.createVesting(addr1.address, add1Amount, 10, 50, 3, [])).to.emit(vestingToken, "CreateVesting").withArgs(addr1.address, add1Amount);
    })
    describe("Create Vesting", function () {
      beforeEach(async function () {
        await vestingToken.createVesting(addr1.address, add1Amount, 10, 50, 3, []);
      })
      it("Should track Create Vesting information of the add1", async function () {
        expect(await vestingToken.availableBalanceOf(addr1.address)).to.equal(0);
        expect(fromWei(await vestingToken.unReleaseAmount(addr1.address))).to.equal('100000000.0');
        expect(fromWei(await vestingToken.balanceOf(addr1.address))).to.equal('100000000.0');
      })
      it("Should fail Create Again of the add1", async function () {
        await expect(vestingToken.createVesting(addr1.address, add1Amount, 10, 50, 3, [])).to.be.revertedWith('contract already exists');
      })
      it("Should fail First receive amount of the add1", async function () {
        await expect(vestingToken.release(addr1.address)).to.be.revertedWith('vesting timing no start');
      })
      it("Should fail if no available amount transfer", async function () {
        await expect(vestingToken.connect(addr1).transfer(deployer.address, 1)).to.be.revertedWith('Insufficient available balance');
      })
      it("Should fail get param of the add1", async function () {
        await expect(vestingToken.nowReleaseAllAmount(addr1.address)).to.be.revertedWith('vesting timing no start');
        await expect(vestingToken.nextReleaseTime(addr1.address)).to.be.revertedWith('vesting timing no start');
        await expect(vestingToken.endReleaseTime(addr1.address)).to.be.revertedWith('vesting timing no start');
      })
    })
    describe("Receive amount", function () {
      describe("Not have first ratio", function () {
        beforeEach(async function () {
          await vestingToken.createVesting(addr1.address, add1Amount, 0, 50, 3, []);
          await vestingToken.startTiming(addr1.address);
        })
        it("Should track now release all amount of the add1", async function () {
          expect(fromWei(await vestingToken.nowReleaseAllAmount(addr1.address))).to.equal('0.0');
        })
        it("Should fail if no time release", async function () {
          await expect(vestingToken.connect(addr1).release(addr1.address)).to.be.revertedWith('No tokens are due');
        })
        it("Should track available balance, when no First receive amount of the add1", async function () {
          expect(fromWei(await vestingToken.availableBalanceOf(addr1.address))).to.equal('0.0');
          expect(fromWei(await vestingToken.unReleaseAmount(addr1.address))).to.equal('100000000.0');
        })
      })
      describe("Have first ratio", function () {
        beforeEach(async function () {
          await vestingToken.createVesting(addr1.address, add1Amount, 10, 50, 3, []);
          await vestingToken.startTiming(addr1.address);
        })
        it("Should updata now release all amount of the add1", async function () {
          expect(fromWei(await vestingToken.nowReleaseAllAmount(addr1.address))).to.equal('10000000.0');
        })
        it("Should track release emit of the add1", async function () {
          await expect(vestingToken.connect(addr1).release(addr1.address)).to.emit(vestingToken, "TokensReleased").withArgs(addr1.address, ethers.utils.parseUnits("10000000", 18));
        })
        it("Should updata available balance, when First receive amount of the add1", async function () {
          await vestingToken.connect(addr1).release(addr1.address);
          expect(fromWei(await vestingToken.availableBalanceOf(addr1.address))).to.equal('10000000.0');
          expect(fromWei(await vestingToken.unReleaseAmount(addr1.address))).to.equal('90000000.0');
        })
      })
      describe("No cliff relese", function () {
        beforeEach(async function () {
          await vestingToken.createVesting(addr1.address, add1Amount, 10, 0, 3, []);
          await vestingToken.startTiming(addr1.address);
        })
        it("Should updata now release all amount of the add1", async function () {
          expect(fromWei(await vestingToken.nowReleaseAllAmount(addr1.address))).to.equal('100000000.0');
        })
        it("Should track release emit of the add1", async function () {
          await expect(vestingToken.connect(addr1).release(addr1.address)).to.emit(vestingToken, "TokensReleased").withArgs(addr1.address, add1Amount);
        })
        it("Should updata available balance, when First receive amount of the add1", async function () {
          await vestingToken.connect(addr1).release(addr1.address);
          expect(fromWei(await vestingToken.availableBalanceOf(addr1.address))).to.equal('100000000.0');
          expect(fromWei(await vestingToken.unReleaseAmount(addr1.address))).to.equal('0.0');
        })
      })

    })
  })
});
