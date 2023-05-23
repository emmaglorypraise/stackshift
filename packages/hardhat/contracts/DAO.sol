// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FARMSUREDAO {

    using SafeMath for uint256;
    
    enum WeatherEvent { None, Drought, ExcessiveRain, Hail }

    // events 

    event NewMember(address indexed _address, uint _votingPower);

    event MemberRemoved(address indexed _address);

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);

    event ProposalVoted(uint256 indexed proposalId, address indexed voter, bool vote);

    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    
    IERC20 public cUSDToken; // cUSDT token contract address

    IERC20 public DAOToken; // cUSDT token contract address
    
    address public owner;

    
    address[] public farmerAddresses;

    Proposal[] public proposals;

    // Weather events and payouts
    uint public droughtThreshold = 20;
    uint public excessiveRainThreshold = 180;
    uint public droughtPayout = 10e6; // 0.01 cUSDT
    uint public excessiveRainPayout = 10e6; // 0.01 cUSDT
    uint public hailPayout = 500e6; // 0.5 cUSDT

    // Policy details
    uint public premium = 500e6; // 0.5 cUSDT
    uint public maxPayout = 1000e6; // 1 cUSDT
    uint public totalPremiumGathered;

    uint public totalInvestment;

    // Farmer details 
    struct Farmer {
        address farmerAddress;
        string farmName;
        string farmDescription;
        string cropType;
        string location;
        uint contribution;
    }

    // Members and proposals
    struct Member {
        address memberAddress;
        uint votingPower;
    }

    struct Proposal {
        address proposer;
        string description;
        uint yesVotes;
        uint noVotes;
        mapping(address => bool) votes;
        bool executed;
    }

    mapping(address => Farmer) public farmers;
    
    mapping(address => uint) public policyholders; // Stores the policyholders and their coverage amount
    
    mapping(address => Member) public members;
    uint public memberCount;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the contract owner can call this function.");
        _;
    }

    constructor(IERC20 _cUSDToken, IERC20 _DAOToken) {
        owner = msg.sender;
        cUSDToken = _cUSDToken;
        DAOToken = _DAOToken;
    }

    // Set the premium amount
    function setPremium(uint _premium) public onlyOwner {
    premium = _premium;
    }

    // Set the maximum payout amount
    function setMaxPayout(uint _maxPayout) public onlyOwner {
    maxPayout = _maxPayout;
    }

    // Set the payout amounts for different weather events
    function setPayoutAmounts(uint _droughtPayout, uint _excessiveRainPayout, uint _hailPayout) public onlyOwner {
    droughtPayout = _droughtPayout;
    excessiveRainPayout = _excessiveRainPayout;
    hailPayout = _hailPayout;
    }

    // Set the thresholds for triggering different weather events
    function setWeatherThresholds(uint _droughtThreshold, uint _excessiveRainThreshold) public onlyOwner {
    droughtThreshold = _droughtThreshold;
    excessiveRainThreshold = _excessiveRainThreshold;
    }

    // Pay the premium to activate the policy
    function payPremium() public {
        require(cUSDToken.transferFrom(msg.sender, address(this), premium), "Failed to transfer premium amount");
        policyholders[msg.sender] = premium;
        totalPremiumGathered += premium;
    }

     // Handle a weather event
    function handleEvent(WeatherEvent eventType, uint value) public {
        require(policyholders[msg.sender] > 0, "You are not a policyholder.");
        require(eventType != WeatherEvent.None, "Invalid weather event");

        uint payout = calculatePayout(eventType, value);
        if (payout > 0) {
            payoutPolicyholder(payout);
        }
    }

    // Calculate the payout amount based on the weather event
    function calculatePayout(WeatherEvent eventType, uint value) internal view returns (uint) {
    uint payout = 0;
    if (eventType == WeatherEvent.Drought && value < droughtThreshold) {
        payout = (droughtThreshold - value) * droughtPayout;
    } else if (eventType == WeatherEvent.ExcessiveRain && value > excessiveRainThreshold) {
        payout = (value - excessiveRainThreshold) * excessiveRainPayout;
    } else if (eventType == WeatherEvent.Hail) {
        payout = hailPayout;
    }
    payout = payout > maxPayout ? maxPayout : payout;
    return payout;
}

    // Payout the policyholder
    function payoutPolicyholder(uint amount) private {
        require(cUSDToken.balanceOf(address(this)) >= amount, "Insufficient contract balance");
        require(cUSDToken.transfer(msg.sender, amount), "Failed to transfer payout amount");
    }

    // Farmers join the risk pool and contribute
    function joinPool(string memory _cropType, string memory _location, uint _contribution) public {
        require(_contribution > 0, "Contribution must be greater than zero");

        Farmer storage newFarmer = farmers[msg.sender];
        newFarmer.cropType = _cropType;
        newFarmer.location = _location;
        newFarmer.contribution = _contribution;

        farmerAddresses.push(msg.sender);
        totalInvestment += _contribution;
    }

    // Farmers leave the risk pool
    function leavePool() public {
        require(farmers[msg.sender].contribution > 0, "You are not a member of the risk pool");

        uint contribution = farmers[msg.sender].contribution;
        delete farmers[msg.sender];

        for (uint i = 0; i < farmerAddresses.length; i++) {
            if (farmerAddresses[i] == msg.sender) {
                farmerAddresses[i] = farmerAddresses[farmerAddresses.length - 1];
                farmerAddresses.pop();
                break;
            }
        }

        totalInvestment -= contribution;
    }

    // Add a new member to the DAO's waitlist
    struct WaitlistedMember {
        uint votingPower;
        bool approved;
    }

    mapping(address => WaitlistedMember) public waitlistedMembers;
    uint public waitlistedMemberCount;

    event MemberApproved(address indexed _address, uint _votingPower);
    event MemberRemovedFromWaitlist(address indexed _address);

    // Join the DAO's waitlist
    function joinWaitlist(uint _votingPower) public {
        require(waitlistedMembers[msg.sender].votingPower == 0, "The address is already on the waitlist.");
        require(_votingPower > 0, "The voting power must be positive.");

        waitlistedMembers[msg.sender] = WaitlistedMember(_votingPower, false);
        waitlistedMemberCount++;

        emit NewMember(msg.sender, _votingPower);
    }

    // Approve a waitlisted member and grant them ERC20 tokens
    function approveMember(address _address) public onlyOwner {
        WaitlistedMember storage waitlistedMember = waitlistedMembers[_address];
        require(waitlistedMember.votingPower > 0, "The address is not on the waitlist.");
        require(!waitlistedMember.approved, "The member has already been approved.");

        members[_address] = Member({
            memberAddress: _address,
            votingPower: waitlistedMember.votingPower
        });
        memberCount--;
        delete waitlistedMembers[_address];
        waitlistedMemberCount--;

        // Transfer ERC20 tokens to the approved member
        uint tokenAmount = 10; // Adjust the token amount as needed
        require(DAOToken.balanceOf(address(this)) >= tokenAmount, "Insufficient token balance in the contract.");
        require(DAOToken.transfer(_address, tokenAmount), "Failed to transfer tokens to the approved member.");

        emit MemberApproved(_address, waitlistedMember.votingPower);
    }

    // Remove a member from the DAO and transfer their ERC20 tokens back to the contract
    function removeMember(address _address) public onlyOwner {

    require(members[_address].votingPower > 0, "The address is not a member.");
    uint votingPower = members[_address].votingPower;
    delete members[_address];
    memberCount--;

    // Transfer ERC20 tokens back to the contract
    uint tokenAmount = 100; // Adjust the token amount as needed
    require(DAOToken.balanceOf(_address) >= 0, "Insufficient DAO token balance in the member's account.");
    require(DAOToken.transferFrom(_address, address(this), tokenAmount), "Failed to transfer DAO tokens from the removed member.");

    emit MemberRemoved(_address); 

    }

    // Create a new proposal
    function createProposal(string memory _description) public {
        require(members[msg.sender].votingPower > 0, "Only members can create proposals");

        uint proposalId = proposals.length;

        // Create the proposal without the 'votes' mapping
        Proposal memory newProposal = Proposal({
            proposer: msg.sender,
            description: _description,
            yesVotes: 0,
            noVotes: 0,
            executed: false
        });

        // Add the proposal to the array
        proposals.push(newProposal);

        emit ProposalCreated(proposalId, msg.sender, _description);
    }

    // Vote on a proposal
    function vote(uint _proposalId, bool _vote) public {
    require(members[msg.sender].votingPower > 0, "Only members can vote");
    require(_proposalId < proposals.length, "Invalid proposal ID");
    require(!proposals[_proposalId].executed, "The proposal has already been executed");
    require(!proposals[_proposalId].votes[msg.sender], "The member has already voted on this proposal");

    Proposal storage proposal = proposals[_proposalId];
    proposal.votes[msg.sender] = true;

    if (_vote) {
        proposal.yesVotes += members[msg.sender].votingPower;
    } else {
        proposal.noVotes += members[msg.sender].votingPower;
    }

    emit ProposalVoted(_proposalId, msg.sender, _vote);

    }


    // Withdraw contract balance
    function withdrawBalance() public onlyOwner {   
        require(address(this).balance > 0, "Contract balance is zero.");
        payable(owner).transfer(address(this).balance);
    }


}