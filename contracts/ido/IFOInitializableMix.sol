// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./interfaces/ILfgProfile.sol";
import "./ICake.sol";
/**
 * @title IFOInitializableBase
 */
abstract contract IFOInitializableMix is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant REWARD_DURATION = 30;

    address public WETH;
    // The address of the smart chef factory
    address public IFO_FACTORY;

    // The LP token used
    IERC20 public raiseToken;
    // The offering token
    IERC20 public offeringToken;

    ICake public iLfg;

    // The block number when IFO starts
    uint256 public startAt;
    // The block number when IFO ends
    uint256 public endAt;

    // It maps the address to pool id to UserInfo
    mapping(address => UserInfo) public userInfo;

    EnumerableSet.AddressSet private investUsers;
    /** flat poolInfo */
    uint256 public raisingAmountPool; // amount of tokens raised for the pool (in LP tokens)
    uint256 public offeringAmountPool; // amount of tokens offered for the pool (in offeringTokens)
    uint256 public limitPerUserInLP; // limit of tokens per user (if 0, it is ignored)
    uint256 public floorLimitPerUserInLP;
    uint256 public totalAmountStake; // total amount pool deposited (in LP tokens)
    /** flat poolInfo */
    // for iCake mapping scale
    uint256 public raiseScaleMolecular;
    uint256 public raiseScaleDenominator;

    // Struct that contains each user information for both pools
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided for pool
        bool claimed; // Whether the user has claimed (default: false) for pool
        uint256 pending;
        uint256 debt;
    }

    // ****** referral ******
    mapping(address => uint256) public referralPoint;
    mapping(address => uint256) public referralCount;
    mapping(address => address) public referralBy;
    mapping(address => bool) public referralAble;

    uint256 public floorAmountReferralTicket;
    uint256 public floorAmountReferralInvest;

    uint256 public referralRewardScale; // based 10000 , 10 means 0.1%
    uint256 public investRewardScale;   // based 10000

    uint256 public totalRewardPoint;    //  based raise token amount point
    uint256 public totalRewardOffered;  //  based raise token amount additional

    mapping(address => address[]) public referralLeaf;

    bool    public enableReferral;
    // ****** referral END ******

    /** Referral Start  */
    uint256 public accRewardPerShare;
    uint256 public rewardPerStep; // reward per 30s
    uint256 public lastRewardAt;
    address public stakeRewardToken;
    bool    public enableStakeMint;
    /** Referral END  */

    // Admin withdraw events
    event AdminWithdraw(uint256 amountLP, uint256 amountOfferingToken);

    // Admin recovers token
    event AdminTokenRecovery(address tokenAddress, uint256 amountTokens);

    // Deposit event
    event Deposit(address indexed user, uint256 amount);

    // Harvest event
    event Harvest(address indexed user, uint256 offeringAmount, uint256 excessAmount);

    // Event for new start & end blocks
    event NewStartAndEnd(uint256 startAt, uint256 endAt);

    // Event when parameters are set for one of the pools
    event PoolParametersSet(uint256 offeringAmountPool, uint256 raisingAmountPool);

    event HarvestReferralReward(address indexed user, uint256 rewardAmount);
    // Modifier to prevent contracts to participate
    modifier notContract() {
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    /**
     * @notice It initializes the contract
     * @dev It can only be called once.
     * @param _raiseToken: the LP token used
     * @param _offeringToken: the token that is offered for the IFO
     * @param _startAt: the start block for the IFO
     * @param _endAt: the end block for the IFO
     * @param _adminAddress: the admin address for handling tokens
     */
    function initialize(
        address _WETH,
        address _raiseToken,
        address _offeringToken,
        uint256 _startAt,
        uint256 _endAt,
        address _adminAddress,
        address _iLfg,
        uint256 _raiseScaleMolecular,
        uint256 _raiseScaleDenominator
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        IFO_FACTORY = msg.sender;
        WETH = _WETH;

        raiseToken = IERC20(_raiseToken);
        offeringToken = IERC20(_offeringToken);
        startAt = _startAt;
        endAt = _endAt;

        iLfg = ICake(_iLfg);

        raiseScaleMolecular = _raiseScaleMolecular;
        raiseScaleDenominator = _raiseScaleDenominator;

        // Transfer ownership to admin
        transferOwnership(_adminAddress);
    }

    function initializeReferral(
        uint256 _floorAmountReferralTicket,
        uint256 _floorAmountReferralInvest,
        uint256 _referralRewardScale, // based 10000 , 10 means 0.1%
        uint256 _investRewardScale,   // based 10000
        uint256 _referralRewardAmount,
        bool    _enableReferral
    ) public onlyOwner {

        totalRewardOffered = _referralRewardAmount;

        floorAmountReferralTicket = _floorAmountReferralTicket;
        floorAmountReferralInvest = _floorAmountReferralInvest;

        referralRewardScale = _referralRewardScale; // based 10000 , 10 means 0.1%
        investRewardScale = _investRewardScale;   // based 10000

        enableReferral = _enableReferral;
    }

    function initializeMint(
        uint256 _rewardPerStep,
        address _rewardToken
    ) external onlyOwner {
        rewardPerStep = _rewardPerStep; // reward per 30s
        stakeRewardToken = _rewardToken;
        enableStakeMint = true;
    }

    /**
     * @notice It allows users to harvest from pool
     */
    function harvestPool() external nonReentrant notContract {

        // Checks whether it is too early to harvest
        require(block.timestamp > endAt, "Harvest: Too early");
        
        beforeHarvest(msg.sender);
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        // Checks whether the user has participated
        require(user.amount > 0, "Harvest: Did not participate");
        // Checks whether the user has already harvested
        require(!user.claimed, "Harvest: Already done");

        // Updates the harvest status
        user.claimed = true;

        // Initialize the variables for offering, refunding user amounts, and tax amount
        (
            uint256 offeringTokenAmount,
            uint256 refundingTokenAmount
        ) = calculateOfferingAndRefundingAmountsPool(msg.sender);

        // Transfer these tokens back to the user if quantity > 0
        if (offeringTokenAmount > 0) {
            // Transfer the tokens at TGE 
            // will never offer NativeToken
            offeringToken.safeTransfer(msg.sender, offeringTokenAmount);
            emit Harvest(msg.sender, offeringTokenAmount, refundingTokenAmount);
        }

        if (refundingTokenAmount > 0) {
            raiseTokenSafeTransfer(msg.sender, refundingTokenAmount);
        }

        if(enableStakeMint) {

            uint256 stakeAmount = pendingReward(msg.sender);
            user.pending = stakeAmount;
            user.debt = stakeAmount;
            //withdraw pending
            IERC20(stakeRewardToken).safeTransfer(msg.sender, stakeAmount);
        }

        if(enableReferral) {
            _withdrawReferralReward(msg.sender);
        }
    }

    function updatePool() internal {
        if(enableStakeMint) {
            // reward per 30s
            uint256 currentRound = block.timestamp > endAt ? endAt / REWARD_DURATION : block.timestamp / REWARD_DURATION;
            // update Acc
            if(lastRewardAt == 0) {
                lastRewardAt = currentRound;
            }
            if(lastRewardAt < currentRound ) {
                uint256 multiplier = currentRound - lastRewardAt;
                uint256 reward = rewardPerStep.mul(multiplier);

                accRewardPerShare = accRewardPerShare.add(
                    reward.mul(1e12).div(totalAmountStake)
                );

                lastRewardAt = currentRound;
            }
        }
    }
    /**
     * @notice It allows users to deposit LP tokens to pool
     * @param _amount: the number of LP token used (18 decimals)
     * @param _amount: the number of LP token used (18 decimals)
     */
    function _depositPool(address account, address referral, uint256 _amount) internal nonReentrant {
        // Checks that pool was set
        require(
            offeringAmountPool > 0 && raisingAmountPool > 0,
            "Deposit: Pool not set"
        );
        // Checks whether the block number is not too early
        require(block.timestamp >= startAt, "Deposit: Too early");
        // Checks whether the block number is not too late
        require(block.timestamp <= endAt, "Deposit: Too late");
        // Checks that the amount deposited is not inferior to 0
        require(_amount > 0, "Deposit: Amount must be > 0");
        require(
                _amount <= getUserCredit(account),
                "Deposit: New amount above user limit"
        );
        updatePool();
        UserInfo storage user = userInfo[account];
        // isSpecialSale ignore
        if(address(iLfg) != address(0)) {
            uint256 ifoCredit = getUserCredit(account);
            require(user.amount.add(_amount) <= ifoCredit, "Not enough IFO credit left");
        }
        if(enableStakeMint && user.amount > 0) {
            user.pending = user.pending.add( 
                user.amount.mul(accRewardPerShare).div(1e12).sub(user.debt)
            );
        }
        // Update the user status
        user.amount = user.amount.add(_amount);
        // Check if the pool has a limit per user
        if (limitPerUserInLP > 0) {
            require(
                user.amount >= floorLimitPerUserInLP,
                "Deposit: New amount less user min limit"
            );
        }
        
        // Updates the totalAmount for pool
        totalAmountStake = totalAmountStake.add(_amount);
        // update debt
        if(enableStakeMint) {
            user.debt = user.amount.mul(accRewardPerShare).div(1e12);
        }

        if(enableReferral) {
            _referralCalculate(referral, account, _amount);
        }

        if(!investUsers.contains(account) ) {
            investUsers.add(account);
        }

        emit Deposit(account, _amount);
    }

    function _referralCalculate(address referral, address invest, uint256 investAmount) private {

        // user referral able
        if( !referralAble[invest] 
        ) {
            uint256 amount = userInfo[invest].amount;
            if(investAmount + amount >= floorAmountReferralTicket) {
                referralAble[invest] = true;
            }
        }
        // referral record
        if( referralBy[invest] == address(0) &&
            referral != address(0)  &&
            referral != invest  &&
            referralAble[referral] && 
            investAmount >= floorAmountReferralInvest
        ) {
            referralBy[invest] = referral;
            referralCount[referral] = referralCount[referral].add(1);
            referralLeaf[referral].push(invest);
        }
        // add point
        address myReferral = referralBy[invest];
        if( myReferral != address(0)
            && investAmount >= floorAmountReferralInvest
        ) {
            uint256 referralReward = investAmount.mul(referralRewardScale).div(10000);
            uint256 investReward = investAmount.mul(investRewardScale).div(10000);

            referralPoint[myReferral] += referralReward;
            referralPoint[invest] += investReward;

            totalRewardPoint = totalRewardPoint.add(referralReward).add(investReward);
        }
    }

    function _withdrawReferralReward(address user) private {

        uint256 rewardAmount = userReferralReward(user);
        if(rewardAmount > 0) {
            offeringToken.safeTransfer(user, rewardAmount);
            emit HarvestReferralReward(user, rewardAmount);
        }
    }

    function userReferralReward(address user) public view returns (uint256 rewardAmount) {
       uint256 point = referralPoint[user];
        if(point > 0 && totalRewardPoint > 0 ) {
            //expect data
            uint256 offering = totalRewardOffered;

            rewardAmount = point.mul(offering).div(totalRewardPoint);
        } 
    }

    function setReferralReward(uint256 _referralRewardAmount) external onlyOwner {
        totalRewardOffered = _referralRewardAmount;
    }

    function getUserCredit(address user) public view returns (uint256) {
        if(address(iLfg) == address(0)) {
            uint256 _limitPerUserInLP = limitPerUserInLP;
            if(referralCount[user] >= 5) {
                _limitPerUserInLP = _limitPerUserInLP * 2;
            }
            uint256 amount = userInfo[user].amount;
            if(_limitPerUserInLP <= amount) {
                return 0;
            } else {
                return _limitPerUserInLP.sub(amount);
            }
        } else {
            uint256 lfgCredit = iLfg.getUserCredit(user);
            return lfgCredit.mul(raiseScaleMolecular).div(raiseScaleDenominator);
        }
    }

    /**
     * @notice It allows the admin to withdraw funds
     * @param _lpAmount: the number of LP token to withdraw (18 decimals)
     * @param _offerAmount: the number of offering amount to withdraw
     * @dev This function is only callable by admin.
     */
    function finalWithdraw(uint256 _lpAmount, uint256 _offerAmount) external onlyOwner {
        require(_lpAmount <= raiseToken.balanceOf(address(this)), "Operations: Not enough LP tokens");
        require(_offerAmount <= offeringToken.balanceOf(address(this)), "Operations: Not enough offering tokens");

        if (_lpAmount > 0) {
            // raiseToken.safeTransfer(msg.sender, _lpAmount);
            raiseTokenSafeTransfer(msg.sender, _lpAmount);
        }

        if (_offerAmount > 0) {
            offeringToken.safeTransfer(msg.sender, _offerAmount);
        }

        emit AdminWithdraw(_lpAmount, _offerAmount);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw (18 decimals)
     * @param _tokenAmount: the number of token amount to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(raiseToken), "Recover: Cannot be LP token");
        require(_tokenAddress != address(offeringToken), "Recover: Cannot be offering token");

        IERC20(_tokenAddress).safeTransfer(msg.sender, _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /**
     * @notice It sets parameters for pool
     * @param _offeringAmountPool: offering amount (in tokens)
     * @param _raisingAmountPool: raising amount (in LP tokens)
     * @param _limitPerUserInLP: limit per user (in LP tokens)
     * @dev This function is only callable by admin.
     */
    function setPool(
        uint256 _offeringAmountPool,
        uint256 _raisingAmountPool,
        uint256 _limitPerUserInLP,
        uint256 _minLimitPerUserInLP
    ) external onlyOwner {

        offeringAmountPool = _offeringAmountPool;
        raisingAmountPool = _raisingAmountPool;
        limitPerUserInLP = _limitPerUserInLP;

        floorLimitPerUserInLP = _minLimitPerUserInLP;

        emit PoolParametersSet(_offeringAmountPool, _raisingAmountPool);
    }

    function setRaiseScale(uint256 _raiseScaleMolecular, uint256 _raiseScaleDenominator) external onlyOwner {
        raiseScaleMolecular     = _raiseScaleMolecular;
        raiseScaleDenominator   = _raiseScaleDenominator;
    }

    /**
     * @notice It allows the admin to update start and end blocks
     * @param _startAt: the new start block
     * @param _endAt: the new end block
     * @dev This function is only callable by admin.
     */
    function updateStartAndEndAt(uint256 _startAt, uint256 _endAt) external onlyOwner {
        require(_startAt < _endAt, "Operations: New startAt must be lower than new endAt");

        startAt = _startAt;
        endAt = _endAt;

        emit NewStartAndEnd(_startAt, _endAt);
    }

    function setOfferingToken(address _offeringToken) external onlyOwner {
         offeringToken = IERC20(_offeringToken);
    }

    /**
     * @notice It returns the pool information
     */
    function viewPoolInfo()
        external
        view
        returns (
            uint256 poolStartAt,
            uint256 poolEndAt,
            uint256 raiseAmount,
            uint256 offeringAmount,
            uint256 minStakeAmount,
            uint256 maxStakeAmount,
            uint256 currentTotalStake,
            bool enableReferralReward,
            bool enableMintReward
        )
    {
        return (
            startAt,
            endAt,
            raisingAmountPool,
            offeringAmountPool,
            floorLimitPerUserInLP,
            limitPerUserInLP,
            totalAmountStake,
            enableReferral,
            enableStakeMint
        );
    }

    function viewUserInfo(address account) public view returns (
        uint256 amount,
        uint256 userStakeReward,
        uint256 userCredit,
        uint256 offeringTokenAmount,
        uint256 refundingTokenAmount,
        bool    userClaimed
    ) {
        UserInfo storage user = userInfo[account];

        (
            uint256 _offeringTokenAmount,
            uint256 _refundingTokenAmount
        ) = calculateOfferingAndRefundingAmountsPool(account);

        return (
            // deposit Amount
            user.amount,
            pendingReward(account),
            getUserCredit(account),
            _offeringTokenAmount,
            _refundingTokenAmount,
            user.claimed
        );
    }

    function viewReferralLeaf(address user) public view returns (address[] memory) {
        return referralLeaf[user];
    }

    function pendingReward(address _user) public view returns(uint256) {
        if(!enableStakeMint) {
            return 0;
        }
        UserInfo storage user = userInfo[_user];
        uint256 accPerShare = accRewardPerShare;
        uint256 lpSupply = totalAmountStake;
        uint256 currentRound = block.timestamp > endAt ? endAt / REWARD_DURATION : block.timestamp / REWARD_DURATION;

        if (lastRewardAt < currentRound && lpSupply != 0) {
            uint256 multiplier = currentRound - lastRewardAt;
            uint256 reward = rewardPerStep.mul(multiplier);

            accPerShare = accPerShare.add(
                reward.mul(1e12).div(totalAmountStake)
            );
        }

        return user.amount.mul(accPerShare).div(1e12).sub(user.debt).add(user.pending);
    }

    function getCurrentRound() public view returns (uint256) {
        return block.timestamp > endAt ? endAt / REWARD_DURATION : block.timestamp / REWARD_DURATION;
    }

    function userReferralInfo(address user) 
        external 
        view 
        returns (
            bool _referralAble,
            address _referralBy,
            uint256 _referralCount,
            uint256 _rewardPoint,
            uint256 rewardOfferTokenAmount,
            address[] memory leaf
        ) { 
        _referralAble = referralAble[user];
        _referralBy = referralBy[user];
        
        if(_referralAble) {
            _rewardPoint = referralPoint[user];
            _referralCount = referralCount[user];

            if(totalRewardOffered > 0 && _rewardPoint > 0) {
                rewardOfferTokenAmount = _rewardPoint.mul(totalRewardOffered).div(totalRewardPoint);
            }
        }

        leaf = referralLeaf[user];
    }

    /**
     * @notice Returns the amount of offering token that can be withdrawn by the owner
     * @return The amount of offering token
     */
    function getWithdrawableOfferingTokenAmount() public view returns (uint256) {
        return offeringToken.balanceOf(address(this));
    }

    /**
     * @notice It calculates the offering amount for a user and the number of LP tokens to transfer back.
     * @param _user: user address
     * and the tax (if any, else 0)
     */
    function calculateOfferingAndRefundingAmountsPool(address _user)
        public
        view
        returns (
            uint256 userOfferingAmount,
            uint256 userRefundingAmount
        )
    {

        if (totalAmountStake > raisingAmountPool) {
            // Calculate allocation for the user
            uint256 allocation = _getUserAllocationPool(_user);

            // Calculate the offering amount for the user based on the offeringAmount for the pool
            userOfferingAmount = offeringAmountPool.mul(allocation).div(1e12);

            // Calculate the payAmount
            uint256 payAmount = raisingAmountPool.mul(allocation).div(1e12);

            // Calculate the pre-tax refunding amount
            userRefundingAmount = userInfo[_user].amount.sub(payAmount);
        } else {
            userRefundingAmount = 0;
            // userInfo[_user] / (raisingAmount / offeringAmount)
            userOfferingAmount = userInfo[_user].amount.mul(offeringAmountPool).div(
                raisingAmountPool
            );
        }
    }

    /**
     * @notice It returns the user allocation for pool
     * @dev 100,000,000,000 means 0.1 (10%) / 1 means 0.0000000000001 (0.0000001%) / 1,000,000,000,000 means 1 (100%)
     * @param _user: user address
     * @return It returns the user's share of pool
     */
    function _getUserAllocationPool(address _user) internal view returns (uint256) {
        if (totalAmountStake > 0) {
            return userInfo[_user].amount.mul(1e18).div(totalAmountStake.mul(1e6));
        } else {
            return 0;
        }
    }

    /**
     * @notice Check if an address is a contract
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    function raiseTokenSafeTransferFrom(address from, address to, uint256 amount) internal {

        if(address(raiseToken) != WETH) {
            raiseToken.safeTransferFrom(from, to, amount);
        } else {
            require(msg.value == amount, "RaiseToken value insufficient");
        }
    }

    function raiseTokenSafeTransfer(address to, uint256 amount) private {

        if(address(raiseToken) != WETH) {
            raiseToken.safeTransfer(to, amount);
        } else {
            payable(to).transfer(amount);
        }
    }

    function beforeDeposit(address user, uint256 amount) internal virtual { }
    function beforeHarvest(address user) internal virtual { }

    function totalInvestCount() public view returns (uint256) {
        return investUsers.length();
    }

    function investAt(uint256 index) public view returns (address) {
        
        if(index < investUsers.length()) {
            return investUsers.at(index);
        }
    }

}