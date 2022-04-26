//SPDX-License-Identifier: MIT
// BNBit Smart Contract
pragma solidity >=0.8.13 <0.9.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface Liquidity {
    function initiate() external;

    // function can only be called once
    function setBNBit(address bnbit) external;

    function getBalance() external view returns (uint256);
}

/**
 * Official Contract for the BNBit Community
 * This contract is Ownable and ownership would be held
 * till the community grows and the governance contract is deployed.
 */
contract BNBit is Ownable, ReentrancyGuard {
    // use safe math library to make maths easier
    using Math for uint256;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // investment constants
    uint256 private constant MIN_DEPOSIT = 0.01 ether;
    uint256 private constant MAX_DEPOSIT = 10000 ether;

    // rewards constants
    uint8 private constant MAX_REFERRAL_LEVEL = 5;
    uint8 private constant MIN_REWARDS_PERCENT = 10; // 1% multiplied by  10
    uint32 private constant MAX_REWARDS_PERCENT = 2000; // 200% multiplied by 10
    uint32 private constant REWARD_PERIOD = 10; // 24 hours

    // project constants
    address private immutable developerAddress;
    address private immutable liquidityAddress;

    // investment statistics
    uint256 public totalInvested;
    uint256 public totalInvestors;
    uint256 public totalWithdrawn;

    // project variables
    uint256 private _percentage;
    uint256 private maxBalance;

    struct Investment {
        uint256 amount;
        uint256 startTime;
        uint256 withdrawn;
    }

    struct Investor {
        uint256 regTime;
        uint256 percent;
        uint256 withdrawnBonus;
        bool whitelisted;
        EnumerableSet.AddressSet downlines;
        Investment[] investments;
    }

    mapping(address => bool) private moderators;
    mapping(address => Investor) private investors;

    // contract events
    event NewInvestment(address indexed investor, uint256 amount);
    event Withdrawal(address indexed investor, uint256 amount);
    event Whitelist(address indexed investor);
    event YieldPercentage(uint256 percent);

    modifier onlyModerator() {
        require(
            moderators[msg.sender] || msg.sender == owner(),
            "Only moderators can perform this action"
        );
        _;
    }

    modifier onlyInvestor() {
        require(
            investors[msg.sender].regTime > 0,
            "You need to invest to perform this action"
        );
        _;
    }

    constructor(address _developer, address _liquidity) {
        developerAddress = _developer;
        liquidityAddress = _liquidity;
        moderators[developerAddress] = true;
        Liquidity(_liquidity).setBNBit(address(this));
    }

    function invest(address _referrer) external payable {
        require(
            _referrer == owner() || investors[_referrer].regTime > 0,
            "Referrer must be registered"
        );

        // register a new investor
        if (investors[msg.sender].regTime == 0) {
            investors[msg.sender].regTime = block.timestamp;
            investors[_referrer].downlines.add(msg.sender);
            totalInvestors++;
        }

        _investBnb(msg.value);

        // add the amount to the total amount invested
        _increaseBalance(msg.value);
    }

    function withdraw(uint256 _investmentID) external onlyInvestor {
        Investment storage investment = investors[msg.sender].investments[
            _investmentID
        ];

        (, uint256 _withdraw, , , ) = getInvestment(_investmentID);

        investment.withdrawn += _withdraw;

        _withdrawBalance(investment.withdrawn);
    }

    function withdrawBonus() external onlyInvestor {
        uint256 _bonus = _getBonus(msg.sender, 0) -
            investors[msg.sender].withdrawnBonus;
        require(_bonus > 0, "No more referral bonus to withdraw");
        investors[msg.sender].withdrawnBonus += _bonus;
        _withdrawBalance(_bonus);
    }

    function reInvest(uint256 _investmentID) external onlyInvestor {
        Investment storage investment = investors[msg.sender].investments[
            _investmentID
        ];

        (, uint256 _amount, , , ) = getInvestment(_investmentID);

        investment.withdrawn += _amount;

        _investBnb(_amount);
    }

    function setModerator(address _moderator, bool status) external onlyOwner {
        moderators[_moderator] = status;
    }

    function setWhitelist(address _investor, bool _status)
        external
        onlyModerator
    {
        require(
            investors[_investor].regTime > 0,
            "Address must belong to an investor"
        );
        investors[_investor].whitelisted = _status;
        investors[_investor].percent += 1;
        emit Whitelist(_investor);
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }

    function percentage() external view returns (uint256) {
        return _percentage.div(10);
    }

    function profile()
        external
        view
        returns (
            bool whitelisted,
            uint256 downlines,
            uint256 investments,
            uint256 regTime
        )
    {
        whitelisted = investors[msg.sender].whitelisted;
        downlines = investors[msg.sender].downlines.length();
        investments = investors[msg.sender].investments.length;
        regTime = investors[msg.sender].regTime;
    }

    function getInvestment(uint256 _investmentID)
        public
        view
        onlyInvestor
        returns (
            uint256 percent,
            uint256 earnings,
            uint256 amount,
            uint256 rewardTime,
            uint256 withdrawn
        )
    {
        Investment memory investment = investors[msg.sender].investments[
            _investmentID
        ];

        rewardTime = (block.timestamp - investment.startTime).div(
            REWARD_PERIOD
        );

        // yield percent earned
        (percent, amount) = _calculatePercent(investment, rewardTime);

        // amount earned within reward time
        (, earnings) = amount.mul(percent).div(1000).trySub(
            investment.withdrawn
        );

        // we multiplied percentages by 10 to get a safe value,
        // so divide to get real percentage
        percent = percent.div(10);
        withdrawn = investment.withdrawn;
    }

    function bonus() external view onlyInvestor returns (uint256) {
        return _getBonus(msg.sender, 0) - investors[msg.sender].withdrawnBonus;
    }

    function _getBonus(address _investor, uint256 _level)
        internal
        view
        returns (uint256 amount)
    {
        if (_level < MAX_REFERRAL_LEVEL) {
            for (
                uint256 i = 0;
                i <
                investors[_investor].downlines.length().min(MAX_REFERRAL_LEVEL);
                i++
            ) {
                amount += investors[investors[_investor].downlines.at(i)]
                    .investments[0]
                    .amount
                    .div(8000);
            }
        }
    }

    function _investBnb(uint256 _amount) internal {
        require(
            _amount >= MIN_DEPOSIT,
            "Amount must be greater than or equal to 0.01BNB"
        );
        require(
            _amount <= MAX_DEPOSIT,
            "Amount must be less than or equal to 10,000BNB"
        );

        investors[msg.sender].investments.push(
            Investment({
                amount: _amount,
                startTime: block.timestamp,
                withdrawn: 0
            })
        );

        emit NewInvestment(msg.sender, _amount);
        totalInvested += _amount;
    }

    function _calculateYield(uint256 _amount) internal {
        uint256 _balance = address(this).balance;

        _percentage += _amount
            .max(_balance)
            .sub(_amount.min(_balance))
            .mul(100)
            .div(_amount.max(_balance));

        if (_balance > maxBalance) {
            maxBalance = _balance;
        }
        emit YieldPercentage(_percentage);
    }

    function _calculatePercent(Investment memory investment, uint256 rewardTime)
        internal
        view
        returns (uint256 percent, uint256 amount)
    {
        amount = investment.amount;

        percent = rewardTime.mul(11).min(MAX_REWARDS_PERCENT);

        if (percent < MAX_REWARDS_PERCENT) {
            percent += _percentage + investors[msg.sender].percent;
        }

        if (
            investors[msg.sender].whitelisted &&
            percent < MAX_REWARDS_PERCENT &&
            investors[msg.sender].downlines.length() > 10
        ) {
            // increase whitelist percent for extra downlines
            percent += MIN_REWARDS_PERCENT;
        }

        // VIP Investor get extra 0.1% for every 10 BNB
        if (
            amount > 10 ether &&
            amount < 1000 ether &&
            percent < MAX_REWARDS_PERCENT
        ) {
            percent += amount.div(10 ether);
        }

        // investor gets extra 1% for holding for 10days
        if (
            percent < MAX_REWARDS_PERCENT &&
            rewardTime > 10 &&
            investment.withdrawn == 0
        ) {
            percent += MIN_REWARDS_PERCENT;
        }
    }

    function _increaseBalance(uint256 _amount) internal nonReentrant {
        (bool _sent, ) = developerAddress.call{value: _amount.div(10)}("");
        (bool _liquidate, ) = liquidityAddress.call{
            value: _amount.mul(5).div(10)
        }("");
        require(_sent, "Failed to send funds to developer");
        require(_liquidate, "Failed to send funds to liquidity pool");

        _calculateYield(_amount);
    }

    function _withdrawBalance(uint256 _amount) internal nonReentrant {
        uint256 _balance = address(this).balance;
        require(_amount > 0, "Specify a bigger amount to withdraw");
        require(_balance > _amount, "Amount too big to be withdrawn");

        (, uint256 __balance) = _balance.trySub(_amount);
        require(__balance > 0, "Withdrawal cannot be proccesed");
        (, _percentage) = _percentage.trySub(__balance.mul(100).div(_balance));

        // transfer the requested amount
        (bool _success, ) = msg.sender.call{value: _amount}("");
        require(_success, "Funds were not withdrawn");

        totalWithdrawn += _amount;

        // return ether to the contract if the balance is less than the max balance
        if (__balance < maxBalance.mul(3).div(10)) {
            Liquidity(liquidityAddress).initiate();
        }

        emit YieldPercentage(_percentage);
        emit Withdrawal(msg.sender, _amount);
    }

    receive() external payable {
        _calculateYield(msg.value);
    }
}
