//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Insurance Protocol
 * @dev A peer-to-peer insurance system where users can create pools, stake tokens, and file claims
 */
contract DecentralizedInsuranceProtocol {
    
    struct InsurancePool {
        uint256 poolId;
        string poolName;
        string coverageType;
        uint256 premiumRate; // Premium rate in basis points (100 = 1%)
        uint256 totalStaked;
        uint256 totalCoverage;
        uint256 maxClaimAmount;
        bool isActive;
        address creator;
        uint256 createdAt;
    }
    
    struct Policy {
        uint256 poolId;
        address holder;
        uint256 coverageAmount;
        uint256 premiumPaid;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }
    
    struct Claim {
        uint256 claimId;
        uint256 poolId;
        address claimant;
        uint256 claimAmount;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 votingDeadline;
        bool isResolved;
        bool isApproved;
        uint256 createdAt;
    }

    // === Storage ===
    mapping(uint256 => InsurancePool) public insurancePools;
    mapping(uint256 => mapping(address => uint256)) public stakedAmounts;
    mapping(uint256 => mapping(address => Policy)) public policies;
    mapping(uint256 => Claim) public claims;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(address => uint256) public stakerRewards;
    mapping(uint256 => address[]) public stakers;

    uint256 public nextPoolId = 1;
    uint256 public nextClaimId = 1;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant MIN_STAKE = 0.1 ether;
    uint256 public constant STAKER_REWARD_RATE = 500; // 5% in basis points

    // === Events ===
    event PoolCreated(uint256 indexed poolId, string poolName, address creator);
    event TokensStaked(uint256 indexed poolId, address indexed staker, uint256 amount);
    event PolicyPurchased(uint256 indexed poolId, address indexed holder, uint256 coverageAmount);
    event ClaimFiled(uint256 indexed claimId, uint256 indexed poolId, address claimant, uint256 amount);
    event ClaimVoted(uint256 indexed claimId, address indexed voter, bool vote);
    event ClaimResolved(uint256 indexed claimId, bool approved, uint256 payoutAmount);
    event RewardsClaimed(address indexed staker, uint256 amount);

    // === Modifiers ===
    modifier onlyActivePool(uint256 _poolId) {
        require(insurancePools[_poolId].isActive, "Pool is not active");
        _;
    }
    
    modifier onlyValidClaim(uint256 _claimId) {
        require(claims[_claimId].claimId != 0, "Claim does not exist");
        require(!claims[_claimId].isResolved, "Claim already resolved");
        _;
    }

    // === Core Functions ===

    function createInsurancePool(
        string memory _poolName,
        string memory _coverageType,
        uint256 _premiumRate,
        uint256 _maxClaimAmount
    ) external payable {
        require(msg.value >= MIN_STAKE, "Insufficient initial stake");
        require(_premiumRate > 0 && _premiumRate <= 10000, "Invalid premium rate");
        require(_maxClaimAmount > 0, "Invalid max claim amount");
        
        uint256 poolId = nextPoolId++;
        insurancePools[poolId] = InsurancePool({
            poolId: poolId,
            poolName: _poolName,
            coverageType: _coverageType,
            premiumRate: _premiumRate,
            totalStaked: msg.value,
            totalCoverage: 0,
            maxClaimAmount: _maxClaimAmount,
            isActive: true,
            creator: msg.sender,
            createdAt: block.timestamp
        });

        stakedAmounts[poolId][msg.sender] = msg.value;
        stakers[poolId].push(msg.sender);

        emit PoolCreated(poolId, _poolName, msg.sender);
        emit TokensStaked(poolId, msg.sender, msg.value);
    }

    function stakeTokens(uint256 _poolId) external payable onlyActivePool(_poolId) {
        require(msg.value >= MIN_STAKE, "Minimum stake not met");

        if (stakedAmounts[_poolId][msg.sender] == 0) {
            stakers[_poolId].push(msg.sender);
        }

        stakedAmounts[_poolId][msg.sender] += msg.value;
        insurancePools[_poolId].totalStaked += msg.value;

        emit TokensStaked(_poolId, msg.sender, msg.value);
    }

    function purchasePolicy(
        uint256 _poolId,
        uint256 _coverageAmount,
        uint256 _coverageDuration
    ) external payable onlyActivePool(_poolId) {
        require(_coverageAmount > 0, "Coverage amount must be greater than 0");
        require(_coverageAmount <= insurancePools[_poolId].maxClaimAmount, "Coverage exceeds max");
        require(_coverageDuration >= 30 days, "Minimum coverage duration is 30 days");
        require(policies[_poolId][msg.sender].holder == address(0), "Policy already exists");

        uint256 premiumAmount = calculatePremium(_poolId, _coverageAmount, _coverageDuration);
        require(msg.value >= premiumAmount, "Insufficient premium payment");

        policies[_poolId][msg.sender] = Policy({
            poolId: _poolId,
            holder: msg.sender,
            coverageAmount: _coverageAmount,
            premiumPaid: premiumAmount,
            startTime: block.timestamp,
            endTime: block.timestamp + _coverageDuration,
            isActive: true
        });

        insurancePools[_poolId].totalCoverage += _coverageAmount;

        uint256 rewardAmount = (premiumAmount * STAKER_REWARD_RATE) / 10000;
        distributeRewards(_poolId, rewardAmount);

        emit PolicyPurchased(_poolId, msg.sender, _coverageAmount);

        if (msg.value > premiumAmount) {
            payable(msg.sender).transfer(msg.value - premiumAmount);
        }
    }

    function fileClaim(
        uint256 _poolId,
        uint256 _claimAmount,
        string memory _description
    ) external onlyActivePool(_poolId) {
        Policy memory policy = policies[_poolId][msg.sender];
        require(policy.isActive, "No active policy");
        require(block.timestamp >= policy.startTime && block.timestamp <= policy.endTime, "Outside coverage period");
        require(_claimAmount > 0 && _claimAmount <= policy.coverageAmount, "Invalid claim amount");

        uint256 claimId = nextClaimId++;
        claims[claimId] = Claim({
            claimId: claimId,
            poolId: _poolId,
            claimant: msg.sender,
            claimAmount: _claimAmount,
            description: _description,
            votesFor: 0,
            votesAgainst: 0,
            votingDeadline: block.timestamp + VOTING_PERIOD,
            isResolved: false,
            isApproved: false,
            createdAt: block.timestamp
        });

        emit ClaimFiled(claimId, _poolId, msg.sender, _claimAmount);
    }

    function voteOnClaim(uint256 _claimId, bool _approve) external onlyValidClaim(_claimId) {
        Claim storage claim = claims[_claimId];
        require(block.timestamp <= claim.votingDeadline, "Voting ended");
        require(stakedAmounts[claim.poolId][msg.sender] > 0, "Only stakers can vote");
        require(!hasVoted[_claimId][msg.sender], "Already voted");

        hasVoted[_claimId][msg.sender] = true;
        uint256 votingPower = stakedAmounts[claim.poolId][msg.sender];

        if (_approve) {
            claim.votesFor += votingPower;
        } else {
            claim.votesAgainst += votingPower;
        }

        emit ClaimVoted(_claimId, msg.sender, _approve);
    }

    function resolveClaim(uint256 _claimId) external onlyValidClaim(_claimId) {
        Claim storage claim = claims[_claimId];
        require(block.timestamp > claim.votingDeadline, "Voting not finished");

        bool approved = claim.votesFor > claim.votesAgainst;
        claim.isResolved = true;
        claim.isApproved = approved;

        uint256 payout = 0;

        if (approved) {
            payout = claim.claimAmount;
            require(address(this).balance >= payout, "Insufficient funds");
            policies[claim.poolId][claim.claimant].isActive = false;
            payable(claim.claimant).transfer(payout);
        }

        emit ClaimResolved(_claimId, approved, payout);
    }

    function claimRewards() external {
        uint256 reward = stakerRewards[msg.sender];
        require(reward > 0, "No rewards");

        stakerRewards[msg.sender] = 0;
        payable(msg.sender).transfer(reward);

        emit RewardsClaimed(msg.sender, reward);
    }

    function calculatePremium(uint256 _poolId, uint256 _coverageAmount, uint256 _duration) public view returns (uint256) {
        uint256 annualPremium = (_coverageAmount * insurancePools[_poolId].premiumRate) / 10000;
        return (annualPremium * _duration) / 365 days;
    }

    function distributeRewards(uint256 _poolId, uint256 rewardAmount) internal {
        uint256 totalStaked = insurancePools[_poolId].totalStaked;
        if (totalStaked == 0 || rewardAmount == 0) return;

        for (uint256 i = 0; i < stakers[_poolId].length; i++) {
            address staker = stakers[_poolId][i];
            uint256 stake = stakedAmounts[_poolId][staker];
            if (stake > 0) {
                uint256 rewardShare = (rewardAmount * stake) / totalStaked;
                stakerRewards[staker] += rewardShare;
            }
        }
    }

    // === ✅ New Function: Unstake Tokens ===
    function unstakeTokens(uint256 _poolId, uint256 _amount) external onlyActivePool(_poolId) {
        require(_amount > 0, "Amount must be greater than zero");
        require(stakedAmounts[_poolId][msg.sender] >= _amount, "Not enough staked");

        for (uint256 i = 1; i < nextClaimId; i++) {
            Claim memory claim = claims[i];
            if (
                claim.poolId == _poolId &&
                !claim.isResolved &&
                block.timestamp <= claim.votingDeadline &&
                hasVoted[i][msg.sender]
            ) {
                revert("Cannot unstake during active voting");
            }
        }

        stakedAmounts[_poolId][msg.sender] -= _amount;
        insurancePools[_poolId].totalStaked -= _amount;
        payable(msg.sender).transfer(_amount);
    }
}
