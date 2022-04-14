//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

contract BNBit is Ownable, ReentrancyGuard {
    // use safe math library to make maths easier
    using SafeMath for uint256;

    // investment constants
    uint256 private constant MIN_DEPOSIT = 100000 gwei;
    uint256 private constant MAX_DEPOSIT = 10000 ether;
    uint256 private constant INIT_INVESTOR = 9999;

    // rewards constants
    uint256 private constant MAX_LEVEL = 5;
    uint256 private constant MIN_REWARDS = 1;
    uint256 private constant MAX_REWARDS = 200;
    uint256 private constant REWARD_PERIOD = 86400; // 24 hours

    // current count of investors
    uint256 private investorCount = INIT_INVESTOR;
    // last time invest was called
    uint256 private lastInvestmentTime = block.timestamp;
    // address of investment processor
    address private investmentProcessor;

    // contract variables
    uint256 private contractBalance;
    uint256 private liquidityBalance;
    uint256 private developerFee;

    // investment statistics
    uint256 public yieldPercent;
    uint256 public totalInvestment;
    uint256 public totalRewards;
    uint256 public totalWithdrawals;

    // investment events
    event Investment(address indexed investor, uint256 amount);
    event YieldIncrease(uint256 percent);
    event RewardInvestors(uint256 count);

    // investor struct
    struct Investor {
        // id of our investor
        uint256 id;
        // a  portfolio index
        uint256[] investments;
        // start time for each investment
        uint256[] rewardTimes;
        // rewards are paid in increments of yields%
        uint256[] rewards;
        // yields percentages
        uint256[] yields;
        // current track of yield percentage
        uint256[] rewardTrack;
        // referral bonuses
        uint256 bonuses;
        // id of referrer
        uint256 uplineId;
        // count of direct referrals
        uint256 downlineCount;
        // is investor whitelisted,  defaults to false
        bool whitelisted;
        bool active;
    }

    // a map of moderators
    mapping(address => bool) public moderators;
    // a map of investor id
    mapping(uint256 => address) public investorIds;
    // a map of investors
    mapping(address => Investor) public investors;

    // checks if sender is a moderator
    modifier onlyModerator() {
        require(
            moderators[msg.sender] || msg.sender == owner(),
            "Only moderators can call this function"
        );
        _;
    }

    constructor(address _processor) payable {
        investmentProcessor = _processor;
        investors[msg.sender].active = true;
        investors[msg.sender].uplineId = investorCount;
        investorIds[investorCount] = msg.sender;
        // any amount sent with deployment is saved
        addContractBalance();
    }

    /**
     * @dev gets amount in contract balance
     * @return uint256
     */
    function balance() public view returns (uint256) {
        return contractBalance;
    }

    /**
     * @dev gets count of investors
     * @return uint256
     */
    function numInvestors() public view returns (uint256) {
        return investorCount - INIT_INVESTOR;
    }

    /**
     * @dev processes investment using upline ID. set to 9999 if none
     */
    function invest(uint256 _uplineId) public payable {
        require(
            msg.value >= MIN_DEPOSIT && msg.value <= MAX_DEPOSIT,
            "Deposit amount must be between 1 and 100000 BNB"
        );
        require(
            _uplineId <= investorCount && _uplineId >= INIT_INVESTOR,
            "Upline must be an investor"
        );
        require(
            block.timestamp > lastInvestmentTime,
            "Must wait between investments"
        );

        // investor has not registered yet
        if (!investors[msg.sender].active) {
            require(
                investors[investorIds[_uplineId]].active,
                "Upline is not registered!"
            );
            investorCount++;
            investorIds[investorCount] = msg.sender;
            investors[msg.sender].id = investorCount;
            investors[msg.sender].uplineId = _uplineId;
            payReferrals(msg.value, _uplineId, 1);
        }
        investors[msg.sender].investments.push(msg.value);
        investors[msg.sender].yields.push(MIN_REWARDS);
        investors[msg.sender].rewardTimes.push(block.timestamp);
        investors[msg.sender].rewards.push(0);
        investors[msg.sender].active = true;

        // add 0.1% for every 10BNB upto 1000BNB to investors
        if (msg.value >= 10 ether && msg.value <= 1000 ether) {
            uint256 i = investors[msg.sender].yields.length - 1;
            investors[msg.sender].yields[i] += toPerth(100, 1);
        }

        // update investment stats
        addContractBalance();
        totalInvestment += msg.value;

        // emit event
        emit Investment(msg.sender, msg.value);

        // update last investment time to prevent spam by miners
        lastInvestmentTime = block.timestamp;
    }

    /**
     * @dev process withdrawals of investment rewards
     * @param _withdrawalAmount amount to withdraw
     */
    function withdraw(uint256 _withdrawalAmount, uint256 _investmentID)
        public
        payable
        nonReentrant
    {
        require(
            investors[msg.sender].active == true,
            "Must be an active investor"
        );
        require(
            _withdrawalAmount <= investors[msg.sender].rewards[_investmentID],
            "Withdrawal amount must be less than or equal to the total rewards"
        );
        require(
            _withdrawalAmount <= contractBalance,
            "Withdrawal amount must be less than or equal to contract balance"
        );

        // update contract balance
        removeContractBalance(_withdrawalAmount);
        investors[msg.sender].rewards[_investmentID] -= _withdrawalAmount;
        // reset yield percentage
        investors[msg.sender].yields[_investmentID] = MIN_REWARDS;
        // update total totalWithdrawals
        totalWithdrawals += _withdrawalAmount;

        // send funds to sender
        payable(msg.sender).transfer(_withdrawalAmount);
    }

    /**
     * @dev process withdrawals of referral bonuses
     */
    function withdrawBonus() public payable nonReentrant {
        require(
            investors[msg.sender].active == true,
            "Must be an active investor"
        );
        require(investors[msg.sender].bonuses > 0, "No bonus to withdraw");
        require(
            investors[msg.sender].bonuses <= contractBalance,
            "Bonus amount must be less than or equal to contract balance"
        );

        // update contract balance
        removeContractBalance(investors[msg.sender].bonuses);
        // update total totalWithdrawals
        totalWithdrawals += investors[msg.sender].bonuses;

        payable(msg.sender).transfer(investors[msg.sender].bonuses);
        investors[msg.sender].bonuses = 0;
    }

    /**
     * @dev process payment of investment rewards
     */
    function processInvestment() public {
        require(
            msg.sender == investmentProcessor || msg.sender == owner(),
            "Only investment processor bot or owner can call this function"
        );
        require(contractBalance > 0, "Contract balance must be greater than 0");

        for (uint256 i = INIT_INVESTOR; i < investorCount; i++) {
            // dont pay after 200% is attained
            if (investors[investorIds[i]].active) {
                payRewards(investorIds[i]);
            }
        }
        emit RewardInvestors(investorCount);
    }

    /**
     * @dev add amount to contract balance
     */
    function addContractBalance() public payable nonReentrant {
        if (msg.value > 0) {
            uint256 _lastbal = contractBalance;
            contractBalance += msg.value.mul(30).div(100);
            liquidityBalance += msg.value.mul(70).div(100);
            yieldPercent = contractBalance.sub(_lastbal).mul(100).div(
                contractBalance
            );
            emit YieldIncrease(yieldPercent);
        }
    }

    /**
     * @dev remove from contract balance
     * @param _amount amount to remove
     */
    function removeContractBalance(uint256 _amount) public {
        require(_amount > 0, "Amount is too small to remove");
        yieldPercent = (100 * (contractBalance - _amount)) / contractBalance;
        contractBalance -= _amount;
        emit YieldIncrease(yieldPercent);
    }

    /**
     * @dev sets an investor's whitelist status
     * @param _investor address of the investor
     * @param _status boolean of the whitelist status
     */
    function setWhitelist(address _investor, bool _status)
        public
        onlyModerator
    {
        investors[_investor].whitelisted = _status;
    }

    /**
     * @dev sets fee used for marketing and paying developers - 10% of total
     */
    function setDeveloperFee() public onlyOwner {
        developerFee = (liquidityBalance + contractBalance).mul(10).div(100);
    }

    /**
     * @dev removes fee used for marketing and paying developers
     */
    function removeDeveloperFee() public payable onlyOwner nonReentrant {
        require(developerFee > 0, "Developer fee must be greater than 0");
        payable(msg.sender).transfer(developerFee);
    }

    /**
     * @dev adds a new moderator
     * @param _moderator address of the new moderator
     */
    function addModerator(address _moderator) public onlyOwner {
        moderators[_moderator] = true;
    }

    /**
     * @dev removes a moderator
     * @param _moderator address of the moderator
     */
    function removeModerator(address _moderator) public onlyOwner {
        moderators[_moderator] = false;
    }

    /**
     * @dev pays referral bonus upto fifth level
     * @param _id id of the investor's upline
     * @param _level level determines amount of the referral bonus
     */
    function payReferrals(
        uint256 _amount,
        uint256 _id,
        uint256 _level
    ) internal {
        address _investor = investorIds[_id];
        Investor memory upline = investors[_investor];
        require(upline.active == true, "Upline must be an active investor");

        investors[_investor].downlineCount = upline.downlineCount + 1;

        if (_level < MAX_LEVEL) {
            if (upline.downlineCount <= MAX_LEVEL) {
                investors[_investor].bonuses += toPerth(_amount, 80 / _level);
                // pay next upline
                payReferrals(_amount, upline.uplineId, _level + 1);
            } else if (
                upline.downlineCount >= 20 && investors[_investor].whitelisted
            ) {
                // pay the whhitelisted upline 0.1% of amount
                investors[_investor].bonuses += toPerth(_amount, 1) / 10;
            }
        }
    }

    /**
     * @dev pays investment rewards to investor
     * @param _investor address of the investor
     */
    function payRewards(address _investor) internal {
        Investor memory investor = investors[_investor];
        for (uint256 i = 0; i < investor.rewardTimes.length; i++) {
            uint256 investment = (investor.investments[i] * 3) / 10;
            // pay users daily as long as sum total yield is not greater than 200%
            if (
                block.timestamp - investor.rewardTimes[i] >= REWARD_PERIOD &&
                investor.rewardTrack[i] < 200
            ) {
                uint256 reward = toPerth(investment, investor.yields[i]);
                totalRewards += reward;
                investors[_investor].rewards[i] += reward;

                // update investor's reward track
                investors[_investor].rewardTrack[i] += investors[_investor]
                    .yields[i];
                // increase the yield percent
                investors[_investor].yields[i] += yieldPercent;
            }
            // pay more rewards after 10 days
            if (
                block.timestamp - investor.rewardTimes[i] >=
                (REWARD_PERIOD * 10)
            ) {
                investors[_investor].rewards[i] += toPerth(investment, 1);
            }
            // update time of last reward
            investor.rewardTimes[i] = block.timestamp;
        }
    }

    /**
     * @dev gets an investor by id address
     * @return investor of the investor
     */
    function profile() public view returns (Investor memory investor) {
        return investors[msg.sender];
    }

    /**
     * @dev converts amount to amount per thousand
     * @param _amount amount to convert
     * @param _perth degree to convert to per thousand
     * @return per thousand amount
     */
    function toPerth(uint256 _amount, uint256 _perth)
        internal
        pure
        returns (uint256)
    {
        return _amount.mul(_perth).div(1000);
    }
}
