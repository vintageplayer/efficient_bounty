// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

// Avax Fuji Address - 0x1707bD6EE1A07765AB5a106E78Db4C887487e68A

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract EfficientBounty is ChainlinkClient{
    using Chainlink for Chainlink.Request;

    address issuer;
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    mapping(uint => string) requestResults;
    mapping(uint => uint) requestingAPIBountyIds;
    mapping(address => uint[]) userRequests;
    string constant baseUrl = "https://api.github.com/repos";

    enum BountyStatus {CREATED, ACTIVE, COMPLETED, CANCELLED}

    struct Bid {
        address developer;
        uint bid_amount;
        bool is_active;
    }
    
    struct Bounty {
        address creator;
        uint amount;
        uint bid_amount;
        BountyStatus status;
        uint finishDeadline;
        string organization_name;
        string repository_name;
        string issue_number;
        Bid bid;
    }

    uint bounty_count;
    mapping(uint=>Bounty) bounties;
    mapping(address=>uint[]) user_bounties;
    mapping(address=>uint[]) user_bids;

    event BountyCreated(uint bounty_id, address creator, uint amount);
    event BidAccepted(uint bounty_id, address developer, uint bid_amount);
    event BountyAccepted(uint bounty_id, address developer, uint total_bounty_reward);
    event BountyCancelled(uint bounty_id);

    constructor() {
        setChainlinkToken(0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846);
        oracle = 0xCC80934EAf22b2C8dBf7A69e8E0D356a7CAc5754;
        jobId = "f2d5815a194f42d3b727c688f7c7a176";
        fee = 0.1 * 10 ** 18;
        issuer = msg.sender;
    }

    function createBounty(uint _acceptDeadline, uint _bid_amount, string memory _organization_name, string memory _repository_name, string memory _issue_number)
    public
    payable
    hasValue()
    validDeadline(_acceptDeadline)
    returns(uint) {
        bounty_count += 1;
        bounties[bounty_count].creator = msg.sender;
        bounties[bounty_count].amount = msg.value;
        bounties[bounty_count].bid_amount = _bid_amount;
        bounties[bounty_count].status = BountyStatus.CREATED;
        bounties[bounty_count].finishDeadline = _acceptDeadline;
        bounties[bounty_count].organization_name = _organization_name;
        bounties[bounty_count].repository_name = _repository_name;
        bounties[bounty_count].issue_number = _issue_number;
        user_bounties[msg.sender].push(bounty_count);
        emit BountyCreated(bounty_count, msg.sender, msg.value);
        return bounty_count;
    }

    function bidOnBounty(uint bounty_id)
    public
    payable
    validBidAmount(bounty_id)
    beforeDeadline(bounty_id)
    validateBountyStatus(bounty_id, BountyStatus.CREATED)
    {
        bounties[bounty_id].bid.developer = msg.sender;
        bounties[bounty_id].bid.bid_amount = msg.value;
        bounties[bounty_id].bid.is_active = true;
        bounties[bounty_id].status = BountyStatus.ACTIVE;
        user_bids[msg.sender].push(bounty_id);
        emit BidAccepted(bounty_id, msg.sender, msg.value);
    }

    function acceptBounty(uint bounty_id)
    public
    payable
    isCreator(bounty_id)
    validateBountyStatus(bounty_id, BountyStatus.ACTIVE) {
        bounties[bounty_id].status = BountyStatus.COMPLETED;
        uint total_bounty_reward = bounties[bounty_id].amount + bounties[bounty_id].bid_amount;
        payable(bounties[bounty_id].bid.developer).transfer(total_bounty_reward);
        emit BountyAccepted(bounty_id, bounties[bounty_id].bid.developer, total_bounty_reward);
    }

    /**
     * Receive the response in the form of uint256
     */ 
    function fulfill(bytes32 _requestId, bytes32 issueStatus) public recordChainlinkFulfillment(_requestId)
    {
        requestResults[uint(_requestId)] = bytes32ToString(issueStatus);
    }

    function getRequestResult(uint _requestId) public view 
    returns (string memory) {
        return requestResults[_requestId];
    }

    function getUserRequestIds() public view returns (uint[] memory) {
        return userRequests[msg.sender];
    }

    function getBountyUrl(uint bounty_id) public view 
    returns (string memory) {
        string memory url = string(abi.encodePacked(baseUrl, '/', bounties[bounty_id].organization_name, '/', bounties[bounty_id].repository_name, '/issues/', bounties[bounty_id].issue_number));
        return url;
    }

    function makeApiCall(string memory url) internal returns (bytes32 requestId) 
    {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);        
        request.add("get", url);
        request.add("path", "comparisonCode");
        return sendChainlinkRequestTo(oracle, request, fee);
    }    

    function processBounty(uint bounty_id)
    payable
    public
    isDeveloper(bounty_id)
    validateBountyStatus(bounty_id, BountyStatus.ACTIVE) 
    returns (uint) {
        string memory url = string(abi.encodePacked(baseUrl, '/', bounties[bounty_id].organization_name, '/', bounties[bounty_id].repository_name, '/issues/', bounties[bounty_id].issue_number));
        uint requestId = uint(makeApiCall(url));
        requestingAPIBountyIds[requestId] = bounty_id;
        userRequests[msg.sender].push(requestId);
        return requestId;
    }

    function cancelBounty(uint bounty_id)
    public
    payable
    isCreator(bounty_id)
    BountyNotActiveOrExpired(bounty_id) {
        bounties[bounty_id].status = BountyStatus.CANCELLED;
        uint total_bounty_reward = bounties[bounty_id].amount + bounties[bounty_id].bid_amount;
        payable(bounties[bounty_id].bid.developer).transfer(total_bounty_reward);
        emit BountyCancelled(bounty_id);
    }

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }


    function getBountyCount()
    public
    view
    returns(uint) {
        return bounty_count;
    }

    function getUserCreatedBounties()
    public
    view
    returns(uint[] memory) {
        return user_bounties[msg.sender];
    }

    function getUserBids()
    public
    view
    returns(uint[] memory) {
        return user_bids[msg.sender];
    }

    function getBountyData(uint bounty_id) 
    public
    view
    returns (Bounty memory){
        return bounties[bounty_id];
    }

    modifier hasValue() {
        require(msg.value > 0, "Invalid Transaction Amount!!");
        _;
    }

    modifier validDeadline(uint deadline) {
        require(deadline > block.timestamp, "Deadline needs to be in future!!");
        _;
    }

    modifier validateBountyStatus(uint bounty_id, BountyStatus desiredStatus) {
        require(bounties[bounty_id].status == desiredStatus, "Bounty Not in desiredStatus state");
        _;
    }

    modifier validBidAmount(uint bounty_id) {
        require(bounties[bounty_id].bid_amount == msg.value, "Invalid Bid Amount");
        _;
    }

    modifier beforeDeadline(uint bounty_id) {
        require(bounties[bounty_id].finishDeadline >= block.timestamp, "Bounty Deadline Over");
        _;
    }

    modifier isDeveloper(uint bounty_id) {
        require(bounties[bounty_id].bid.developer == msg.sender, "Unauthorized!! Can be triggered only by the developer working on bounty!!");
        _;
    }

    modifier isCreator(uint bounty_id) {
        require(bounties[bounty_id].creator == msg.sender, "Unauthorized: Not the game creator!!");
        _;
    }

    modifier BountyNotActiveOrExpired(uint bounty_id) {
        require(
            bounties[bounty_id].status == BountyStatus.CREATED 
            || (bounties[bounty_id].status == BountyStatus.ACTIVE && bounties[bounty_id].finishDeadline < block.timestamp),
            "Bounty can't be cancelled when active");
        _;
    }

    modifier isIssuer() {
        require(msg.sender == issuer, "Unauthorized: Not the contract owner!!");
        _;
    }
}
