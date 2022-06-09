// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract TokenVesting is ERC20, Ownable {
    struct Vesting {
        uint256 version;
        uint256 cliff;
        uint256 releaseCount;
        uint256 released;
        uint256 totalLockAmount;
        uint256 firstRatio;
        uint256[] customizeRatio;
    }

    // vesting data
    mapping(address => Vesting) private _vestingOf;
    mapping(uint256 => uint256) private _startTimeOf;

    modifier availableBalance(address _account, uint256 _amount) {
        require(
            _amount <= balanceOf(_account) - unReleaseAmount(_account),
            "Insufficient available balance"
        );
        _;
    }

    modifier haveVesting(address _beneficiary) {
        require(
            _vestingOf[_beneficiary].totalLockAmount == 0 &&
                _vestingOf[_beneficiary].cliff == 0 &&
                _vestingOf[_beneficiary].releaseCount == 0,
            "Vesting already exists"
        );
        _;
    }

    modifier startTimingCheck(address _beneficiary) {
        require(
            _vestingOf[_beneficiary].totalLockAmount > 0,
            "Vesting not exists"
        );
        require(
            _getStartTimestamp(_beneficiary) > 0,
            "Vesting timing no start"
        );
        _;
    }

    event TokensReleased(address beneficiary, uint256 amount);
    event CreateVesting(
        address beneficiary,
        uint256 version,
        uint256 cliff,
        uint256 releaseCount,
        uint256 totalLockAmount,
        uint256 firstRatio,
        uint256[] customizeRatio
    );

    /**
     * @dev Create Vesting
     *
     * @param _beneficiary beneficiary address
     * @param _totalLockAmount totalLock amount
     * @param _firstRatio first ratio
     * @param _cliff cliff
     * @param _releaseCount release count
     * @param _customizeRatio Customize every unlock rate
     *
     */
    function createVesting(
        address _beneficiary,
        uint256 _totalLockAmount,
        uint256 _version,
        uint256 _firstRatio,
        uint256 _cliff,
        uint256 _releaseCount,
        uint256[] memory _customizeRatio
    ) external onlyOwner haveVesting(_beneficiary) {
        require(_beneficiary != address(0), "Beneficiary is the zero address");
        require(_totalLockAmount > 0, "Amount count is 0");
        require(_releaseCount > 0, "Release count is 0");
        require(_firstRatio <= 100, "No more than one hundred");
        if (_customizeRatio.length > 0) {
            require(
                _releaseCount == _customizeRatio.length,
                "The number of unlocks must correspond to the customize ratio array"
            );
            uint256 __total;
            for (uint256 i = 0; i < _customizeRatio.length; i++) {
                __total += _customizeRatio[i];
            }
            require(__total + _firstRatio == 100, "The Ratio total is not 100");
        }
        _vestingOf[_beneficiary] = Vesting(
            _version,
            _cliff,
            _releaseCount,
            0,
            _totalLockAmount,
            _firstRatio,
            _customizeRatio
        );
        transfer(_beneficiary, _totalLockAmount);
        emit CreateVesting(
            _beneficiary,
            _version,
            _cliff,
            _releaseCount,
            _totalLockAmount,
            _firstRatio,
            _customizeRatio
        );
    }

    /**
     * @dev start vesting timing
     * @param _version version
     */
    function setVersionTime(uint256 _version, uint256 _timestamp)
        external
        onlyOwner
    {
        require(
            _timestamp >= block.timestamp,
            "Timestamp cannot be less than current time"
        );
        require(_startTimeOf[_version] == 0, "Time has begun");
        _startTimeOf[_version] = _timestamp;
    }

    /**
     * @dev Unlock this amount for the beneficiary
     * @param _beneficiary beneficiary address
     */
    function release(address _beneficiary)
        external
        startTimingCheck(_beneficiary)
    {
        require(unReleaseAmount(_beneficiary) > 0, "Vesting is done");
        uint256 _nowReleased = nowReleaseAllAmount(_beneficiary);
        require(_nowReleased > 0, "No tokens are due");
        Vesting storage vestingOf_ = _vestingOf[_beneficiary];
        vestingOf_.released += _nowReleased;
        emit TokensReleased(_beneficiary, _nowReleased);
    }

    /**
     * @dev Get the unlocked amount
     * @param _beneficiary beneficiary address
     * @return uint256 token.balance
     */
    function unReleaseAmount(address _beneficiary)
        public
        view
        returns (uint256)
    {
        return
            _vestingOf[_beneficiary].totalLockAmount -
            _vestingOf[_beneficiary].released;
    }

    /**
     * @dev Get all amounts currently unlockable
     * @param _beneficiary beneficiary address
     * @return uint256 token.balance
     */
    function nowReleaseAllAmount(address _beneficiary)
        public
        view
        startTimingCheck(_beneficiary)
        returns (uint256)
    {
        uint256 _nowAmount = _firstAmount(_beneficiary);
        if (
            block.timestamp <
            (_getStartTimestamp(_beneficiary) + _vestingOf[_beneficiary].cliff)
        ) {
            return _nowAmount - _vestingOf[_beneficiary].released;
        } else if (block.timestamp >= endReleaseTime(_beneficiary)) {
            return unReleaseAmount(_beneficiary);
        } else {
            if (_vestingOf[_beneficiary].customizeRatio.length > 0) {
                for (uint256 i = 0; i < _nowReleaseCount(_beneficiary); i++) {
                    _nowAmount += _vestedCustomizeRatioAmount(_beneficiary, i);
                }
            } else {
                _nowAmount +=
                    _singleReleaseAmount(_beneficiary) *
                    _nowReleaseCount(_beneficiary);
            }
            return _nowAmount - _vestingOf[_beneficiary].released;
        }
    }

    /**
     * @dev Get the next unlock time
     * @param _beneficiary beneficiary address
     * @return uint256 block.timestamp
     */
    function nextReleaseTime(address _beneficiary)
        public
        view
        startTimingCheck(_beneficiary)
        returns (uint256)
    {
        uint256 _firstGetTime = _getStartTimestamp(_beneficiary) +
            _vestingOf[_beneficiary].cliff;
        uint256 _nextTime = ((_nowReleaseCount(_beneficiary)) *
            _vestingOf[_beneficiary].cliff) + _firstGetTime;
        if (
            _nextTime >= endReleaseTime(_beneficiary) ||
            block.timestamp >= endReleaseTime(_beneficiary)
        ) {
            return endReleaseTime(_beneficiary);
        } else {
            return _nextTime;
        }
    }

    /**
     * @dev Get the lock-up end time
     * @param _beneficiary beneficiary address
     * @return uint256 block.timestamp
     */
    function endReleaseTime(address _beneficiary)
        public
        view
        startTimingCheck(_beneficiary)
        returns (uint256)
    {
        return
            _getStartTimestamp(_beneficiary) +
            (_vestingOf[_beneficiary].cliff *
                _vestingOf[_beneficiary].releaseCount);
    }

    /**
     * @dev Get the available amount of the current account
     * @param _account beneficiary address
     * @return uint256 token.balance
     */
    function availableBalanceOf(address _account)
        public
        view
        returns (uint256)
    {
        return balanceOf(_account) - unReleaseAmount(_account);
    }

    /**
     * @dev Get Custom Unlock Ratio Amount that should be unlocked
     * @param _beneficiary beneficiary address
     * @return uint256 token.balance
     */
    function _vestedCustomizeRatioAmount(address _beneficiary, uint256 _count)
        private
        view
        returns (uint256)
    {
        return
            (_vestingOf[_beneficiary].totalLockAmount *
                _vestingOf[_beneficiary].customizeRatio[_count]) / 100;
    }

    /**
     * @dev Get a single unlock amount
     * @param _beneficiary beneficiary address
     * @return uint256 token.balance
     */
    function _singleReleaseAmount(address _beneficiary)
        private
        view
        returns (uint256)
    {
        return
            (_vestingOf[_beneficiary].totalLockAmount -
                _firstAmount(_beneficiary)) /
            _vestingOf[_beneficiary].releaseCount;
    }

    /**
     * @dev Get the first unlock amount
     * @param _beneficiary beneficiary address
     * @return uint256 token.balance
     */
    function _firstAmount(address _beneficiary) private view returns (uint256) {
        return
            (_vestingOf[_beneficiary].totalLockAmount *
                _vestingOf[_beneficiary].firstRatio) / 100;
    }

    /**
     * @dev Get the current unlock stage
     * @param _beneficiary beneficiary address
     * @return uint256 number
     */
    function _nowReleaseCount(address _beneficiary)
        private
        view
        returns (uint256)
    {
        return
            (block.timestamp - _getStartTimestamp(_beneficiary)) /
            _vestingOf[_beneficiary].cliff;
    }

    /**
     * @dev Get the start timestamp
     * @param _beneficiary beneficiary address
     * @return uint256 number
     */
    function _getStartTimestamp(address _beneficiary)
        private
        view
        returns (uint256)
    {
        return _startTimeOf[_vestingOf[_beneficiary].version];
    }
}

contract DMTToken is TokenVesting {
    constructor() ERC20("DriveMetaverseToken", "DMT") {
        uint256 initMintAmount = 3000000000;
        _mint(msg.sender, initMintAmount * 10**decimals());
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        override
        availableBalance(_msgSender(), amount)
        returns (bool)
    {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override availableBalance(from, amount) returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        availableBalance(_msgSender(), amount)
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function burn(uint256 amount)
        public
        virtual
        availableBalance(_msgSender(), amount)
        onlyOwner
    {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount)
        public
        virtual
        availableBalance(account, amount)
        onlyOwner
    {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}
