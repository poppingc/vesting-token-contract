// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 *
 * TokenVesting 锁仓合约
 *
 * [功能]
 * 创建锁仓(在用户钱包内);
 * 可设置首次金额解锁(按设置比率);
 * 按设置的间隔时间线性解锁锁仓余额;
 * 合约拥有者可设置撤回受益人剩余未解锁的金额;
 *
 */
abstract contract TokenVesting is ERC20, Ownable {
    // 锁仓数据结构
    struct Vesting {
        // 开始时间
        uint256 start;
        // 间隔时间
        uint256 cliff;
        // 解锁次数
        uint256 releaseCount;
        // 已解锁金额
        uint256 released;
        // 总锁仓金额
        uint256 totalLockAmount;
        // 首次解锁金额比率
        uint256 firstRatio;
        // 定制解锁比率
        uint256[] customizeRatio;
    }

    // 储存 锁仓数据
    mapping(address => Vesting) private _vestingOf;

    // 验证 可用金额
    modifier availableBalance(address _account, uint256 _amount) {
        require(
            _amount <= balanceOf(_account) - unReleaseAmount(_account),
            "TokenVesting: Insufficient available balance"
        );
        _;
    }

    // 验证 已创建 Vesting
    modifier haveVesting(address _beneficiary) {
        require(
            _vestingOf[_beneficiary].start > 0,
            "TokenVesting: Beneficiary no vesting"
        );
        _;
    }

    // 代币解锁
    event TokensReleased(address token, uint256 amount);
    // 撤销代币归属
    event TokenVestingRevoked(address token);

    /**
     * @dev 创建锁仓合约
     *
     * [要求]
     * 只有合约拥有者可创建;
     *
     * @param _beneficiary 受益人地址
     * @param _totalLockAmount 锁仓总金额
     * @param _firstRatio 首次释放金额比率
     * @param _cliff 解锁间隔时间
     * @param _releaseCount 解锁次数
     * @param _customizeRatio 定制每次解锁比率
     *
     */
    function createVesting(
        address _beneficiary,
        uint256 _totalLockAmount,
        uint256 _firstRatio,
        uint256 _cliff,
        uint256 _releaseCount,
        uint256[] memory _customizeRatio
    ) external onlyOwner {
        require(
            _beneficiary != address(0),
            "TokenVesting: beneficiary is the zero address"
        );
        require(_releaseCount > 0, "TokenVesting: Release count is 0");
        require(_firstRatio <= 100, "TokenVesting: No more than one hundred");

        // 如果设置定制解锁比率
        if (_customizeRatio.length > 0) {
            // 验证解锁次数和时间是否对应
            require(
                _releaseCount == _customizeRatio.length,
                "TokenVesting: Unlock times and time do not correspond"
            );

            // 验证总比率是否超出 100%
            uint256 __total;
            for (uint256 i = 0; i < _customizeRatio.length; i++) {
                __total += _customizeRatio[i];
            }
            require(
                __total + _firstRatio == 100,
                "TokenVesting: The Ratio total is not 100"
            );
        }

        // 储存数据
        _vestingOf[_beneficiary] = Vesting(
            block.timestamp,
            _cliff,
            _releaseCount,
            0,
            _totalLockAmount,
            _firstRatio,
            _customizeRatio
        );

        // 转账代币给受益人
        transfer(_beneficiary, _totalLockAmount);
        // 允许合约发布者可以转账未解锁金额
        _approve(_beneficiary, owner(), _totalLockAmount);
    }

    /**
     * @dev 解锁：给受益人解锁本次金额
     * @param _beneficiary 受益人地址
     */
    function release(address _beneficiary) external haveVesting(_beneficiary) {
        require(
            unReleaseAmount(_beneficiary) > 0,
            "TokenVesting: Vesting is done"
        );

        // 现在解锁的金额
        uint256 _nowReleased = nowReleaseAllAmount(_beneficiary);
        require(_nowReleased > 0, "TokenVesting: No tokens are due");

        // 获取 储存的锁仓数据
        Vesting storage vestingOf_ = _vestingOf[_beneficiary];

        vestingOf_.released += _nowReleased;
        _spendAllowance(_beneficiary, owner(), _nowReleased);

        emit TokensReleased(_beneficiary, _nowReleased);
    }

    /**
     * @dev 获取 未解锁金额
     * @param _beneficiary 受益人地址
     * @return uint256 token.balance
     */
    function unReleaseAmount(address _beneficiary)
        public
        view
        returns (uint256)
    {
        // 返回剩余未解锁金额: 总锁仓金额 - 已解锁金额
        return
            _vestingOf[_beneficiary].totalLockAmount -
            _vestingOf[_beneficiary].released;
    }

    /**
     * @dev 获取 当前可解锁的 所有金额
     * @param _beneficiary 受益人地址
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
                // 开始到下一时间的定制解锁比率总金额
                for (uint256 i = 0; i < _nowReleaseCount(_beneficiary); i++) {
                    _nowAmount += _vestedCustomizeRatioAmount(_beneficiary, i);
                }
            } else {
                // 获取 开始到下一时间解锁的总金额 单次解锁金额 * 下一时间解锁阶段数
                _nowAmount +=
                    _singleReleaseAmount(_beneficiary) *
                    _nowReleaseCount(_beneficiary);
            }
            // 返回: 开始到当前时间解锁的总金额 - 已解锁金额
            return _nowAmount - _vestingOf[_beneficiary].released;
        }
    }

    /**
     * @dev 获取 下一个解锁时间
     * @param _beneficiary 受益人地址
     * @return uint256 block.timestamp
     */
    function nextReleaseTime(address _beneficiary)
        public
        view
        returns (uint256)
    {
        // 初次解锁:  开始时间 + 间隔时间
        uint256 _firstGetTime = _vestingOf[_beneficiary].start +
            _vestingOf[_beneficiary].cliff;

        // 下一解锁时间: ((已解锁阶段 * 间隔时间) + 初次解锁时间
        uint256 _nextTime = ((_nowReleaseCount(_beneficiary)) *
            _vestingOf[_beneficiary].cliff) + _firstGetTime;

        if (
            _nextTime >= endReleaseTime(_beneficiary) ||
            block.timestamp >= endReleaseTime(_beneficiary)
        ) {
            // 如果下个时间大于结束时间 或 当前时间大于结束时间，则返回结束时间
            return endReleaseTime(_beneficiary);
        } else {
            // 返回: 已过去的解锁时间 + 间隔时间
            return _nextTime;
        }
    }

    /**
     * @dev 获取 锁仓结束时间
     * @param _beneficiary 受益人地址
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
     * @dev 获取 当前账号可用金额
     * @param _account 受益人地址
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
     * @dev 获取 定制解锁比率 应解锁的金额
     * @param _beneficiary 受益人地址
     * @return uint256 token.balance
     */
    function _vestedCustomizeRatioAmount(address _beneficiary, uint256 _count)
        private
        view
        returns (uint256)
    {
        // 返回: 总金额 * 本次解锁的比率 / 100
        return
            (_vestingOf[_beneficiary].totalLockAmount *
                _vestingOf[_beneficiary].customizeRatio[_count]) / 100;
    }

    /**
     * @dev 获取 单次解锁金额
     * @param _beneficiary 受益人地址
     * @return uint256 token.balance
     */
    function _singleReleaseAmount(address _beneficiary)
        private
        view
        returns (uint256)
    {
        // 返回: ( ( 总锁仓金额 - 首次解锁金额 ) / 解锁次数 )
        return
            (_vestingOf[_beneficiary].totalLockAmount -
                _firstAmount(_beneficiary)) /
            _vestingOf[_beneficiary].releaseCount;
    }

    /**
     * @dev 获取 首次解锁金额
     * @param _beneficiary 受益人地址
     * @return uint256 token.balance
     */
    function _firstAmount(address _beneficiary) private view returns (uint256) {
        // 返回: ( ( 总锁仓金额 * 首次解锁比率(uint) ) / 100 )
        return
            (_vestingOf[_beneficiary].totalLockAmount *
                _vestingOf[_beneficiary].firstRatio) / 100;
    }

    /**
     * @dev 获取 当前解锁阶段
     * @param _beneficiary 受益人地址
     * @return uint256 number
     */
    function _nowReleaseCount(address _beneficiary)
        private
        view
        returns (uint256)
    {
        // 返回: (当前时间 - 开始时间) / 间隔时间)
        return
            (block.timestamp - _vestingOf[_beneficiary].start) /
            _vestingOf[_beneficiary].cliff;
    }

    /**
     * @dev 获取 下一解锁阶段
     * @param _beneficiary 受益人地址
     * @return uint256 number
     */
    function _nextReleaseCount(address _beneficiary)
        private
        view
        returns (uint256)
    {
        // 返回: (下一时间 - 开始时间) / 间隔时间)
        return
            (nextReleaseTime(_beneficiary) - _vestingOf[_beneficiary].start) /
            _vestingOf[_beneficiary].cliff;
    }
}

/**
 *
 * 代币合约
 *
 * [功能]
 * 限制最大发币量;
 * <TokenVesting> 创建锁仓(在用户钱包内);
 *
 */
contract Token is TokenVesting {
    // 验证 是否为空账号
    modifier nonEmptyAddress(address _addr) {
        require(_addr != address(0), "Token: Empty address");
        _;
    }

    /**
     * @dev 初始化
     *
     * @param _initMint 初次铸币数量
     * @param _name 代码名称
     * @param _symbol 代币简称
     *
     */
    constructor(
        uint256 _initMint,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _initMint);
    }

    /**
     * @dev 转账
     * [要求]
     * 不得超过可用余额(锁仓未解锁金额不可使用)
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
     * @dev 从..转账
     * [要求]
     * 不得超过可用余额(锁仓未解锁金额不可使用)
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
     * @dev 授权他人
     * [要求]
     * 不得超过可用余额(锁仓未解锁金额不可使用)
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
     * @dev 销毁调用者的`amount` 代币
     * [要求]
     * 不得超过可用余额(锁仓未解锁金额不可使用)
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
     * @dev 销毁 `account` 中的 `amount` 代币，从调用者的账户中扣除
     * [要求]
     * 不得超过可用余额(锁仓未解锁金额不可使用)
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
}

/**

[Gas消耗 - Remix - JVM (London)]
合约部署: 4,043,998 gas
创建锁仓: 258,069 gas

[Gas消耗 - Remix - Ganache]
合约部署: 3,508,620 gas
创建锁仓: 206,895 gas

[Gas消耗 - Remix - BNB Test]
合约部署: 3,508,620 gas
创建锁仓: 191,943 gas
领取金额: 62,490 gas

*/
