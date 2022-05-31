// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract TokenVesting is ERC20, Ownable {
    struct Vesting {
        uint256 start;
        uint256 cliff;
        uint256 releaseCount;
        uint256 released;
        uint256 totalLockAmount;
        uint256 firstRatio;
        uint256[] customizeRatio;
    }

    // vesting data
    mapping(address => Vesting) private _vestingOf;

    modifier availableBalance(address _account, uint256 _amount) {
        require(
            _amount <= balanceOf(_account) - unReleaseAmount(_account),
            "TokenVesting: Insufficient available balance"
        );
        _;
    }

    modifier haveVesting(address _beneficiary) {
        require(
            _vestingOf[_beneficiary].start == 0,
            "TokenVesting: contract already exists"
        );
        _;
    }

    event TokensReleased(address token, uint256 amount);
    event TokenVestingRevoked(address token);

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
        uint256 _firstRatio,
        uint256 _cliff,
        uint256 _releaseCount,
        uint256[] memory _customizeRatio
    ) external onlyOwner haveVesting(_beneficiary) {
        require(
            _beneficiary != address(0),
            "TokenVesting: beneficiary is the zero address"
        );
        require(_releaseCount > 0, "TokenVesting: Release count is 0");
        require(_firstRatio <= 100, "TokenVesting: No more than one hundred");
        if (_customizeRatio.length > 0) {
            require(
                _releaseCount == _customizeRatio.length,
                "TokenVesting: Unlock times and time do not correspond"
            );
            uint256 __total;
            for (uint256 i = 0; i < _customizeRatio.length; i++) {
                __total += _customizeRatio[i];
            }
            require(
                __total + _firstRatio == 100,
                "TokenVesting: The Ratio total is not 100"
            );
        }
        _vestingOf[_beneficiary] = Vesting(
            block.timestamp,
            _cliff,
            _releaseCount,
            0,
            _totalLockAmount,
            _firstRatio,
            _customizeRatio
        );
        transfer(_beneficiary, _totalLockAmount);
        _approve(_beneficiary, owner(), _totalLockAmount);
    }

    /**
     * @dev Unlock this amount for the beneficiary
     * @param _beneficiary beneficiary address
     */
    function release(address _beneficiary) external {
        require(
            unReleaseAmount(_beneficiary) > 0,
            "TokenVesting: Vesting is done"
        );
        // now unlock amount
        uint256 _nowReleased = nowReleaseAllAmount(_beneficiary);
        require(_nowReleased > 0, "TokenVesting: No tokens are due");
        Vesting storage vestingOf_ = _vestingOf[_beneficiary];
        vestingOf_.released += _nowReleased;
        _spendAllowance(_beneficiary, owner(), _nowReleased);
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
        returns (uint256)
    {
        uint256 _nowAmount = _firstAmount(_beneficiary);
        if (
            block.timestamp <
            (_vestingOf[_beneficiary].start + _vestingOf[_beneficiary].cliff)
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
        returns (uint256)
    {
        uint256 _firstGetTime = _vestingOf[_beneficiary].start +
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
        returns (uint256)
    {
        // 返回: 开始时间 + ( 间隔时间 * 解锁次数 )
        return
            _vestingOf[_beneficiary].start +
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
            (block.timestamp - _vestingOf[_beneficiary].start) /
            _vestingOf[_beneficiary].cliff;
    }

    /**
     * @dev Get the next unlock stage
     * @param _beneficiary beneficiary address
     * @return uint256 number
     */
    function _nextReleaseCount(address _beneficiary)
        private
        view
        returns (uint256)
    {
        return
            (nextReleaseTime(_beneficiary) - _vestingOf[_beneficiary].start) /
            _vestingOf[_beneficiary].cliff;
    }
}

contract VestingToken is TokenVesting {
    uint8 private immutable __decimals;

    modifier nonEmptyAddress(address _addr) {
        require(_addr != address(0), "Token: Empty address");
        _;
    }

    /**
     * @dev constructor
     *
     * @param _initMint first mint amount
     * @param _decimals token decimals
     * @param _name token name
     * @param _symbol token symbol
     *
     */
    constructor(
        uint256 _initMint,
        uint8 _decimals,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        __decimals = _decimals;
        _mint(msg.sender, _initMint * 10**_decimals);
    }

    /**
     * @dev transfer
     */
    function transfer(address to, uint256 amount)
        public
        virtual
        override
        availableBalance(_msgSender(), amount)
        nonEmptyAddress(to)
        returns (bool)
    {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev transferFrom
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        public
        virtual
        override
        availableBalance(from, amount)
        nonEmptyAddress(to)
        returns (bool)
    {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev approve
     */
    function approve(address spender, uint256 amount)
        public
        virtual
        override
        availableBalance(_msgSender(), amount)
        nonEmptyAddress(spender)
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev burn
     */
    function burn(uint256 amount)
        public
        virtual
        availableBalance(_msgSender(), amount)
        onlyOwner
    {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev burnFrom
     */
    function burnFrom(address account, uint256 amount)
        public
        virtual
        availableBalance(account, amount)
        onlyOwner
    {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    /**
     * @dev get decimals
     */
    function decimals() public view override returns (uint8) {
        return __decimals;
    }
}
