//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

/**
 * BNBit Smart Contract
 *
 * @dev Created by BNBit Community for the Community
 */
contract Bnbit is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // the timestamp when contract was deployed
    uint256 public startTime;

    // mapping of moderators
    mapping(address => uint) public moderators;

    // count of moderators
    uint256 public modCount = 1;

    uint256 public liquidityBalance;
    uint256 public contractBalance;
    uint256 public defaultUplineBal;
    uint256 public totalInvestment;
    uint256 public investorCount;
    uint256 public HourlyLastPayment;
    uint256 public DailyLastPayment;
    uint256 public payOutpercentage;

    uint256 private developerFee;
    uint256 private DefaultUplineID = 999;
    uint256 private minimumDeposit = 0.01 ether;
    uint256 private InvestorsID = 112209;
    address private defaultUpline;

    uint256[] whitelist;

    struct Investor {
        bool harvest;
        bool whitelisted;
        bool VIPinvestor;
        address wallet;
        uint256 initialDeposit;
        uint256 partialBalance;
        uint256 balance;
        uint256 uplineId;
        uint256 initInvestmentTimestap;
        uint256 maxHoldBonusTimestamp;
        uint256 dailybonusTimestamp;
        uint256 referralBonus;
    }

    struct Downlines {
        uint256 id1;
        uint256 id2;
        uint256 id3;
        uint256 id4;
        uint256 id5;
    }

    mapping(uint256 => Investor) public investors;
    mapping(uint256 => Downlines) public referrals;
    mapping(address => uint256) public addressToInvestorsID;

    event Investment(
        address investor,
        uint256 amount,
        uint256 uplineId,
        uint256 indexed userId
    );

    event HarvestYieldEvent(
        uint256 investorID,
        address harvesterAddress,
        uint256 time,
        uint256 amountWithdrawed
    );

    event HarvestYieldWhiteListEvent(
        uint256 investorID,
        address harvesterAddress,
        uint256 time,
        uint256 amountWithdrawed
    );

    event AddLiquidityBalanceEvent(uint256 amount, uint256 addedAt);

    event RemoveLiquidityBalanceEvent(uint256 amount, uint256 addedAt);

    event AddToContractBalanceEvent(uint256 amount, uint256 addedAt);

    /**
     * @dev checks for moderators
     */
    modifier isModerator() {
        require(
            moderators[msg.sender] > 0,
            "Only moderators can call this function"
        );
        _;
    }

    /**
     * @dev Constructor
     */
    constructor(address _upline) {
        startTime = block.timestamp;
        moderators[msg.sender] = 9999;
        defaultUpline = _upline;
    }

    /**
     * Start point for all investors
     * processes registration with upline id
     *
     * @param upline uint256 - use 999 as default
     */
    function invest(uint256 upline) public payable {
        require(msg.value >= minimumDeposit, "You Investment is Low");
        if (upline == 999) {
            increment();
            InvestorsID = InvestorsID.add(3);
            uint256 thirty_percent = msg.value.div(100).mul(30);
            uint256 seventy_percent = msg.value.div(100).mul(70);
            liquidityBalance = liquidityBalance.add(seventy_percent);
            uint256 sixteen_percent = msg.value.div(100).mul(16);
            defaultUplineBal = defaultUplineBal.add(sixteen_percent);
            //uint256 newBalance = msg.value.sub(sixteen_percent);
            investors[InvestorsID] = Investor(
                false,
                false,
                false,
                msg.sender,
                msg.value,
                thirty_percent,
                0,
                upline,
                block.timestamp,
                block.timestamp.add(864000),
                block.timestamp.add(86400)
            );
            referrals[InvestorsID] = Downlines(0, 0, 0, 0, 0);
            contractBalance = contractBalance.add(
                thirty_percent - sixteen_percent
            );
            uint256 bonus = VipHoldBonus(msg.value);
            contractBalance = contractBalance.sub(bonus);
            maxContractHoldBonus(msg.value);
            totalInvestment.add(msg.value);
            addressToInvestorsID[msg.sender] = InvestorsID;
            emit Investment(msg.sender, msg.value, upline, InvestorsID);
        }
        if (upline > 112209) {
            // gets the upline investor
            Investor storage directUpline = investors[upline];
            require(
                msg.sender != directUpline.wallet,
                "You can not be you own Upline"
            );
            require(directUpline.VIPinvestor != true, "upline does not Exist");
            increment();
            InvestorsID = InvestorsID.add(5);
            uint256 thirty_percent = msg.value.div(100).mul(30);
            uint256 seventy_percent = msg.value.div(100).mul(70);
            liquidityBalance = liquidityBalance.add(seventy_percent);
            uint256 newuserUpline = getDownline(upline, InvestorsID);
            if (newuserUpline == 999) {
                upline = 999;
            }
            payUpline(upline, msg.value);

            investors[InvestorsID] = Investor(
                false,
                false,
                false,
                msg.sender,
                msg.value,
                thirty_percent,
                0,
                upline,
                block.timestamp,
                block.timestamp.add(864000),
                block.timestamp.add(86400)
            );
            referrals[InvestorsID] = Downlines(0, 0, 0, 0, 0);
            contractBalance = contractBalance.add(thirty_percent);
            uint256 bonus = VipHoldBonus(msg.value);
            contractBalance = contractBalance.sub(bonus);
            uint256 MCHbonus = maxContractHoldBonus(msg.value);
            contractBalance = contractBalance.sub(MCHbonus);
            totalInvestment.add(msg.value);
            addressToInvestorsID[msg.sender] = InvestorsID;
            emit Investment(msg.sender, msg.value, upline, InvestorsID);
        }
    }

    /**
     * Pay all investors based on current APR
     *
     * @param _percent uint256
     */
    function payInvestors(uint256 _percent) public onlyOwner {
        if (contractBalance > 0) {
            for (uint256 index = 112209; index <= InvestorsID; index++) {
                Investor storage investor = investors[index];
                checkPercent(index);
                uint256 userPartialbalance = investor.partialBalance;
                uint256 percentage = userPartialbalance.div(100).mul(_percent);
                //add to user balance which is 30% of actual funds
                if (
                    investor.harvest == false &&
                    block.timestamp >= investor.dailybonusTimestamp
                ) {
                    investor.balance = investor.balance.add(percentage);
                    investor.initInvestmentTimestap = block.timestamp;
                    investor.dailybonusTimestamp = block.timestamp.add(86400);
                    //remove from Contract
                    contractBalance = contractBalance.sub(percentage);
                }
                maxHoldBonus(index);
            }
        }
    }

    /**
     * Adds a investor to whitelist
     *
     * @param _investorID uint256 - The investor to whitelist
     */
    function addToWhiteList(uint256 _investorID) public isModerator {
        whitelist.push(_investorID);
        Investor storage investor = investors[_investorID];
        investor.whitelisted = true;
    }

    /**
     * Processes withdrawal of rewards to wallet of normal investor
     *
     * @param _investorID uint256
     */
    function harvestYield(uint256 _investorID) public nonReentrant {
        Investor storage investor = investors[_investorID];
        require(msg.sender == investor.wallet, "Withdraw Error");
        //sender be owner of account
        require(investor.harvest == true, "You are not ready to harvest");
        require(
            investor.whitelisted == false,
            "Use the WhiteList WithDraw button"
        );
        //harvest must be true
        //make transfer to msg.sender
        payable(msg.sender).transfer(investor.initialDeposit.mul(2));
        contractBalance.sub(investor.initialDeposit.mul(2));
        emit HarvestYieldEvent(
            _investorID,
            msg.sender,
            block.timestamp,
            investor.initialDeposit.mul(2)
        );
    }

    /**
     * Processes withdrawal of rewards to wallet of whitelisted investor
     *
     * @param _investorID uint256
     */
    function harvestYieldWhiteList(uint256 _investorID) public {
        Investor storage investor = investors[_investorID];
        require(msg.sender == investor.wallet, "Withdraw Error");
        //sender be owner of account
        require(investor.harvest == true, "You are not ready to harvest");
        require(investor.whitelisted == true, "Something Went Wrong");
        //harvest must be true
        //make transfer to msg.sender
        payable(msg.sender).transfer(investor.initialDeposit.mul(3));
        contractBalance.sub(investor.initialDeposit.mul(3));
        emit HarvestYieldEvent(
            _investorID,
            msg.sender,
            block.timestamp,
            investor.initialDeposit.mul(2)
        );
    }

    /**
     * Gets the total investment
     *
     * @return uint256
     */
    function calculatePayOut() public payable returns (uint256) {
        return totalInvestment;
    }

    function withdrawfromDefaultWallet() public payable {
        require(msg.sender == defaultUpline, "Only default Owner can Withdraw");
        require(defaultUplineBal > 0);
        payable(msg.sender).transfer(defaultUplineBal);
    }

    /**
     * Adds a moderator which can inturn add whitelists
     *
     * @param _moderator address
     */
    function addModerator(address _moderator) public onlyOwner {
        //push to admin array
        require(moderators[_moderator] == 0, "Moderator Exist Already");
        moderators[_moderator] = modCount;
        modCount++;
    }

    /**
     * Removes a moderator
     *
     * @param _moderator address
     */
    function removeModerator(address _moderator) public onlyOwner {
        require(moderators[_moderator] > 0, "Moderator Does not Exist");
        delete moderators[_moderator];
    }

    /**
     * Add any amount to liquidity balance
     */
    function addLiquidityBalance() public payable onlyOwner {
        uint256 incremental = msg.value;
        require(incremental > 0, "The amount is negligible to add");
        liquidityBalance = liquidityBalance.add(incremental);
        emit AddLiquidityBalanceEvent(msg.value, block.timestamp);
    }

    function removeDeveloperFee() public onlyOwner {
        require(developerFee > 0, "set Developer Fee");
        require(developerFee <= liquidityBalance, "Invalid Input");
        liquidityBalance = liquidityBalance.sub(developerFee);
        payable(msg.sender).transfer(developerFee);
        emit RemoveLiquidityBalanceEvent(developerFee, block.timestamp);
    }

    function setDeveloperFee() public onlyOwner returns (uint256) {
        developerFee = liquidityBalance.div(100).mul(10);
        return developerFee;
    }

    function addToContractBalance(uint256 amount) public onlyOwner {
        require(
            amount > 0 && amount <= liquidityBalance,
            "Invalid Amount Input"
        );
        liquidityBalance = liquidityBalance.sub(amount);
        contractBalance = contractBalance.add(amount);
        emit AddToContractBalanceEvent(amount, block.timestamp);
    }

    /**
     * Pays an investor after holding for 10days
     *
     * @param _investorID uint256
     */
    function maxHoldBonus(uint256 _investorID) private {
        //get investor's detail
        Investor storage investor = investors[_investorID];
        //time must be 10 days after;

        //check 100 percent
        checkPercent(_investorID);
        //check for 200 percent
        checkPercentWhitelist(_investorID);
        //check for harvest
        if (investor.harvest != true) {
            //harvest is not true
            if (investor.maxHoldBonusTimestamp >= block.timestamp) {
                investor.balance.add(investor.partialBalance.mul(100).div(1));
                contractBalance.sub(investor.partialBalance.mul(100).div(1));
            }
            //check timestamp
        }
    }

    /**
     * Checks current percentage to pay Investor
     *
     * @param _investorID uint256
     */
    function checkPercent(uint256 _investorID) private {
        // get the receipient id
        Investor storage investor = investors[_investorID];
        uint256 initialbalance = investor.initialDeposit;
        // get initial balance
        uint256 currentbalance = investor.balance;
        // get current balance
        if (
            currentbalance == initialbalance.mul(1) &&
            investor.whitelisted == false
        ) {
            investor.harvest = true;
        }
        if (
            currentbalance != initialbalance.mul(1) &&
            investor.whitelisted == false
        ) {
            investor.harvest = false;
        }
    }

    /**
     * Checks current percentage to pay whitelisted Investor
     *
     * @param _investorID uint256
     */
    function checkPercentWhitelist(uint256 _investorID) private {
        //get the investor's details
        Investor storage investor = investors[_investorID];
        uint256 initialbalance = investor.initialDeposit;
        //get initial balance
        uint256 currentbalance = investor.balance;
        //get current Balance
        if (currentbalance == initialbalance.mul(2)) {
            investor.harvest = true;
        }
        if (currentbalance != initialbalance.mul(2)) {
            investor.harvest = false;
        }
    }

    /**
     * Pays the uplines of investor
     *
     * @param uplineID uint256
     * @param initDeposit uint256
     */
    function payUpline(uint256 uplineID, uint256 initDeposit) private {
        checkPercent(uplineID);
        incrementUplineWallet(uplineID, initDeposit, 8);
        uint256 grandUpline = getUplineID(uplineID);
        checkPercent(grandUpline);
        incrementUplineWallet(grandUpline, initDeposit, 4);
        uint256 greatgrandUpline = getUplineID(grandUpline);
        checkPercent(greatgrandUpline);
        incrementUplineWallet(greatgrandUpline, initDeposit, 2);
        uint256 grandgreatgrandUpline = getUplineID(greatgrandUpline);
        checkPercent(grandgreatgrandUpline);
        incrementUplineWallet(grandgreatgrandUpline, initDeposit, 1);
        uint256 greatgrandgreatgrandUpline = getUplineID(grandgreatgrandUpline);
        checkPercent(greatgrandgreatgrandUpline);
        incrementUplineWallet(greatgrandgreatgrandUpline, initDeposit, 1);
    }

    /**
     * Increments the upline wallet
     *
     * @param uplineID uint256
     * @param initDeposit uint256
     * @param percent uint256
     * @return uint256
     */
    function incrementUplineWallet(
        uint256 _upline,
        uint256 initDeposit,
        uint256 percentage
    ) private returns (uint256) {
        //get Upline Current InvestWallet Balance =>G1
        Investor storage G1Upline = investors[_upline];
        if (G1Upline.harvest == false) {
            G1Upline.referralBonus = G1Upline.referralBonus.add(
                initDeposit.div(100).mul(percentage)
            );
            G1Upline.balance = G1Upline.balance.add(
                initDeposit.div(100).mul(percentage)
            );
            contractBalance = contractBalance.sub(
                initDeposit.div(100).mul(percentage)
            );
            return (G1Upline.balance);
        }
        return (G1Upline.balance);
    }

    /**
     * Gets the upline of investor
     *
     * @param _investorID uint256
     * @return uint256
     */
    function getUplineID(uint256 _upline) private view returns (uint256) {
        //get Upline Current InvestWallet Balance =>G1
        Investor storage G1Upline = investors[_upline];
        uint256 InvestorG1UplineID = G1Upline.uplineId;
        return (InvestorG1UplineID);
    }

    function VipHoldBonus(uint256 _initDeposit)
        private
        pure
        returns (uint256 vipBonus)
    {
        //where vip is true

        uint256 bonusCount;
        bonusCount = _initDeposit.div(10000000000000000000);
        if (bonusCount >= 1) {
            uint256 bonus = _initDeposit.mul(10).div(10000);
            return bonus.mul(bonusCount);
        }
    }

    /**
     * Pays the investor after holding for 10days
     *
     * @param _investorID uint256
     */
    function maxContractHoldBonus(uint256 _initDeposit)
        private
        pure
        returns (uint256 maxContractBonus)
    {
        uint256 bonusCount;
        bonusCount = _initDeposit.div(100000000000000000000);
        if (bonusCount >= 1) {
            uint256 bonus = _initDeposit.mul(10).div(10000);
            return bonus.mul(bonusCount);
        }
    }

    /**
     * Increment investor count
     */
    function increment() private {
        investorCount = investorCount.add(1);
    }

    /**
     * Gets the downline of investor
     *
     * @param uplineID uint256
     * @param downlineID uint256
     * @return uint256
     */
    function getDownline(uint256 uplineID, uint256 downlineID)
        private
        returns (uint256 downline)
    {
        Downlines storage referral = referrals[uplineID];
        if (
            referral.id1 == 0 &&
            referral.id2 == 0 &&
            referral.id3 == 0 &&
            referral.id4 == 0 &&
            referral.id5 == 0
        ) {
            referral.id1 = downlineID;
        }
        if (
            referral.id1 != 0 &&
            referral.id1 != downlineID &&
            referral.id2 == 0 &&
            referral.id3 == 0 &&
            referral.id4 == 0 &&
            referral.id5 == 0
        ) {
            referral.id2 = downlineID;
        }
        if (
            referral.id1 != 0 &&
            referral.id2 != downlineID &&
            referral.id2 != 0 &&
            referral.id3 == 0 &&
            referral.id4 == 0 &&
            referral.id5 == 0
        ) {
            referral.id3 = downlineID;
        }
        if (
            referral.id1 != 0 &&
            referral.id3 != downlineID &&
            referral.id2 != 0 &&
            referral.id3 != 0 &&
            referral.id4 == 0 &&
            referral.id5 == 0
        ) {
            referral.id4 = downlineID;
        }
        if (
            referral.id1 != 0 &&
            referral.id4 != downlineID &&
            referral.id2 != 0 &&
            referral.id3 != 0 &&
            referral.id4 != 0 &&
            referral.id5 == 0
        ) {
            referral.id5 = downlineID;
        }
        if (
            referral.id1 != 0 &&
            referral.id2 != 0 &&
            referral.id3 != 0 &&
            referral.id4 != 0 &&
            referral.id5 != 0
        ) {
            return 999;
        }
    }
}
