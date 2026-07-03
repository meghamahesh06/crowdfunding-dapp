// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Crowdfunding DApp
/// @notice A simple decentralized crowdfunding contract. Owners create campaigns,
///         contributors send ETH, and funds are released or refunded automatically
///         based on whether the goal was met by the deadline.
contract Crowdfunding {

    // ---------------------------------------------------------------------
    // Data structures
    // ---------------------------------------------------------------------

    struct Campaign {
        address owner;          // who created the campaign
        string title;
        string description;
        uint256 goal;            // funding target, in wei
        uint256 deadline;        // unix timestamp after which campaign is "over"
        uint256 amountRaised;    // running total of contributions
        bool fundsWithdrawn;     // prevents the owner from withdrawing twice
    }

    // campaignId => Campaign
    mapping(uint256 => Campaign) public campaigns;
    uint256 public campaignCount;

    // campaignId => contributor address => amount they personally contributed
    mapping(uint256 => mapping(address => uint256)) public contributions;

    // campaignId => contributor address => have they already claimed a refund?
    mapping(uint256 => mapping(address => bool)) public hasRefunded;

    // ---------------------------------------------------------------------
    // Events (for frontend listening + on-chain audit trail)
    // ---------------------------------------------------------------------

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed owner,
        string title,
        uint256 goal,
        uint256 deadline
    );

    event ContributionMade(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );

    event FundsWithdrawn(
        uint256 indexed campaignId,
        address indexed owner,
        uint256 amount
    );

    event RefundIssued(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );

    // ---------------------------------------------------------------------
    // Create a campaign
    // ---------------------------------------------------------------------

    function createCampaign(
        string memory _title,
        string memory _description,
        uint256 _goal,
        uint256 _durationInSeconds
    ) external returns (uint256) {
        require(_goal > 0, "Goal must be greater than zero");
        require(_durationInSeconds > 0, "Duration must be greater than zero");

        uint256 campaignId = campaignCount;

        campaigns[campaignId] = Campaign({
            owner: msg.sender,
            title: _title,
            description: _description,
            goal: _goal,
            deadline: block.timestamp + _durationInSeconds,
            amountRaised: 0,
            fundsWithdrawn: false
        });

        campaignCount++;

        emit CampaignCreated(campaignId, msg.sender, _title, _goal, campaigns[campaignId].deadline);

        return campaignId;
    }

    // ---------------------------------------------------------------------
    // Contribute
    // ---------------------------------------------------------------------

    function contribute(uint256 _campaignId) external payable {
        Campaign storage campaign = campaigns[_campaignId];

        require(campaign.owner != address(0), "Campaign does not exist");
        require(block.timestamp < campaign.deadline, "Campaign has ended");
        require(msg.value > 0, "Contribution must be greater than zero");

        campaign.amountRaised += msg.value;
        contributions[_campaignId][msg.sender] += msg.value;

        emit ContributionMade(_campaignId, msg.sender, msg.value);
    }

    // ---------------------------------------------------------------------
    // Withdraw funds (owner only, goal met, deadline passed)
    // ---------------------------------------------------------------------

    function withdrawFunds(uint256 _campaignId) external {
        Campaign storage campaign = campaigns[_campaignId];

        require(campaign.owner != address(0), "Campaign does not exist");
        require(msg.sender == campaign.owner, "Only the campaign owner can withdraw");
        require(block.timestamp >= campaign.deadline, "Campaign is still active");
        require(campaign.amountRaised >= campaign.goal, "Funding goal was not met");
        require(!campaign.fundsWithdrawn, "Funds already withdrawn");

        campaign.fundsWithdrawn = true; // set BEFORE transferring (reentrancy protection)

        uint256 amount = campaign.amountRaised;
        (bool success, ) = payable(campaign.owner).call{value: amount}("");
        require(success, "Transfer to owner failed");

        emit FundsWithdrawn(_campaignId, campaign.owner, amount);
    }

    // ---------------------------------------------------------------------
    // Refund (contributor only, goal NOT met, deadline passed)
    // ---------------------------------------------------------------------

    function refund(uint256 _campaignId) external {
        Campaign storage campaign = campaigns[_campaignId];

        require(campaign.owner != address(0), "Campaign does not exist");
        require(block.timestamp >= campaign.deadline, "Campaign is still active");
        require(campaign.amountRaised < campaign.goal, "Funding goal was met, no refunds");
        require(!hasRefunded[_campaignId][msg.sender], "Already refunded");

        uint256 contributedAmount = contributions[_campaignId][msg.sender];
        require(contributedAmount > 0, "You did not contribute to this campaign");

        hasRefunded[_campaignId][msg.sender] = true; // set BEFORE transferring (reentrancy protection)

        (bool success, ) = payable(msg.sender).call{value: contributedAmount}("");
        require(success, "Refund transfer failed");

        emit RefundIssued(_campaignId, msg.sender, contributedAmount);
    }

    // ---------------------------------------------------------------------
    // Reward tier lookup
    // ---------------------------------------------------------------------

    /// @notice Returns a badge based on what % of the goal a single contributor personally covered.
    ///         Gold: >=10% of goal, Silver: >=5% of goal, Bronze: >0%, None: didn't contribute.
    function getRewardTier(uint256 _campaignId, address _contributor) external view returns (string memory) {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.owner != address(0), "Campaign does not exist");

        uint256 contributed = contributions[_campaignId][_contributor];
        if (contributed == 0) {
            return "None";
        }

        if (contributed * 100 >= campaign.goal * 10) {
            return "Gold";
        } else if (contributed * 100 >= campaign.goal * 5) {
            return "Silver";
        } else {
            return "Bronze";
        }
    }

    // ---------------------------------------------------------------------
    // Convenience read function (nice for your frontend + demo)
    // ---------------------------------------------------------------------

    function getCampaign(uint256 _campaignId) external view returns (
        address owner,
        string memory title,
        string memory description,
        uint256 goal,
        uint256 deadline,
        uint256 amountRaised,
        bool fundsWithdrawn
    ) {
        Campaign storage c = campaigns[_campaignId];
        require(c.owner != address(0), "Campaign does not exist");
        return (c.owner, c.title, c.description, c.goal, c.deadline, c.amountRaised, c.fundsWithdrawn);
    }
}