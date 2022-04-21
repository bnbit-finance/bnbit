//SPDX-License-Identifier: MIT
// BNBit Smart Contract
pragma solidity >=0.8.13 <0.9.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/**
* BNBi
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
    uint8 private constant MIN_REWARDS_PERCENT = 1;
    uint8 private constant MAX_REWARDS_PERCENT = 200;
    uint32 private constant REWARD_PERIOD = 86400; // 24 hours

    // investment statistics
    uint256 public totalInvested;
    uint256 public totalInvestors;

    // project variables
    uint256 public balance;
    uint256 public percentage;

    struct Investment {
        uint256 amount;
        uint256 startTime;
        uint256 withdrawn;
    }

    struct Investor {
        uint256 regTime;
        uint256 percent;
        bool whitelisted;
        EnumerableSet.AddressSet downlines;
        Investment[] investments;
    }

    mapping(address => bool) private moderators;
    mapping(address => Investor) private investors;

    event NewInvestment(address indexed investor, uint256 amount);
    event YieldIncrease(uint256 percent);

    modifier onlyModerator() {
        require(
            moderators[msg.sender] || msg.sender == owner(),
            "Only moderators can call this function"
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

    function invest(address _referrer) external payable {
        require(
            msg.value >= MIN_DEPOSIT,
            "Amount must be greater than or equal to 0.01BNB"
        );
        require(
            msg.value <= MAX_DEPOSIT,
            "Amount must be less than or equal to 10,000BNB"
        );
        require(
            _referrer == owner() || investors[_referrer].regTime > 0,
            "Referrer must be registered"
        );

        // register a new investor
        if (investors[msg.sender].regTime == 0) {
            investors[msg.sender].regTime = block.timestamp;
            investors[_referrer].downlines.add(msg.sender);
            // increase whitelist
            if (
                investors[_referrer].downlines.length() > 10 &&
                investors[_referrer].whitelisted
            ) {
                uint256 base = 1;
                investors[_referrer].percent += base.div(10);
            }

            totalInvestors++;
        }

        _investBnb(msg.value);

        // add the amount to the total amount invested
        addContractBalance();
        totalInvested += msg.value;
    }

    function withdraw(uint256 _investmentID) external onlyInvestor {
        Investment storage investment = investors[msg.sender].investments[
            _investmentID
        ];

        (, uint256 _withdraw, ) = getInvestment(_investmentID);

        investment.withdrawn += _withdraw;

        _removeBalance(investment.withdrawn);
    }

    function withdrawBalance(uint256 _amount) external onlyOwner {
        _removeBalance(_amount);
    }

    function withdrawBonus() external onlyInvestor {
        uint256 bonus = _getBonus(msg.sender, 0);
        _removeBalance(bonus);
    }

    function reInvest(uint256 _investmentID) external onlyInvestor {
        Investment storage investment = investors[msg.sender].investments[
            _investmentID
        ];

        (, uint256 _amount, ) = getInvestment(_investmentID);

        investment.withdrawn += _amount;

        _investBnb(_amount);
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
    }

    function addModerator(address _moderator) external onlyOwner {
        moderators[_moderator] = true;
    }

    function removeModerator(address _moderator) external onlyOwner {
        moderators[_moderator] = false;
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

    function addContractBalance() public payable nonReentrant {
        if (msg.value > 0) {
            percentage = msg.value.max(balance).sub(msg.value.min(balance)).div(
                    msg.value.max(balance)
                );
            balance += msg.value;
            emit YieldIncrease(percentage);
        }
    }

    function getInvestment(uint256 _investmentID)
        public
        view
        onlyInvestor
        returns (
            uint256 percent,
            uint256 earnings,
            uint256 amount
        )
    {
        Investment memory investment = investors[msg.sender].investments[
            _investmentID
        ];

        uint256 _rewardTime = (block.timestamp - investment.startTime).div(
            REWARD_PERIOD
        );

        amount = investment.amount;

        // yield percent earned
        percent = factor(_rewardTime).mul(11).div(10).min(MAX_REWARDS_PERCENT);

        if (percent < MAX_REWARDS_PERCENT) {
            percent += percentage;
        }

        // whitelisted investors get extra 0.1% each day
        if (
            investors[msg.sender].whitelisted && percent < MAX_REWARDS_PERCENT
        ) {
            percent += _rewardTime.div(10);
        }

        // VIP Investor get extra 0.1% for every 10 BNB
        if (
            amount > 10 ether &&
            amount < 1000 ether &&
            percent < MAX_REWARDS_PERCENT
        ) {
            percent += amount.div(10 ether).div(10);
        }

        // investor gets extra 1% for holding for 10days
        if (
            percent < MAX_REWARDS_PERCENT &&
            _rewardTime > 10 &&
            investment.withdrawn == 0
        ) {
            percent += MIN_REWARDS_PERCENT;
        }

        // amount earned within reward time
        (, earnings) = amount.mul(percent).div(10).trySub(investment.withdrawn);
    }

    function getBonus() external view onlyInvestor returns (uint256 bonus) {
        bonus += _getBonus(msg.sender, 0);
    }

    function _getBonus(address _investor, uint256 _level)
        internal
        view
        returns (uint256 bonus)
    {
        if (_level < MAX_REFERRAL_LEVEL) {
            for (
                uint256 i = 0;
                i <
                investors[_investor].downlines.length().min(MAX_REFERRAL_LEVEL);
                i++
            ) {
                bonus += investors[investors[_investor].downlines.at(i)]
                    .investments[0]
                    .amount
                    .mul(8)
                    .div(2)
                    .div(100);
            }
        }
    }

    function _investBnb(uint256 _amount) internal {
        require(_amount > 0, "Amount to invest is too small");

        investors[msg.sender].investments.push(
            Investment({
                amount: _amount,
                startTime: block.timestamp,
                withdrawn: 0
            })
        );

        emit NewInvestment(msg.sender, _amount);
    }

    function _removeBalance(uint256 amount) internal nonReentrant {
        require(amount > 0, "Specify a bigger amount to withdraw");
        require(balance > amount, "Amount too big to be withdrawn");

        (, uint256 newBalance) = balance.trySub(amount);
        percentage -= newBalance.mul(100).div(balance);

        // update the balance
        balance = newBalance;

        // transfer the requested amount
        payable(msg.sender).transfer(amount);
    }

    function factor(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) {
            return 0;
        } else if (x <= 30) {
            return x * factor(x - 1);
        }
    }
}
