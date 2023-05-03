// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LosslessGovernance.sol";
import "@kleros/arbitrable-proxy-contracts/contracts/ArbitrableProxy.sol";
import "@kleros/kleros/contracts/kleros/KlerosLiquid.sol";

contract VotingInvocation {
    address public governor;
    LosslessGovernance public losslessGovernance;
    IArbitrableProxy public arbitrableProxy;
    KlerosLiquid public klerosLiquid;

    uint256 public courtID;
    uint256 public numberOfJurors;
    string public metaevidenceURI;

    mapping(uint256 => uint256) public reportIDToDisputeID;
    mapping(uint256 => bool) public executedReports;

    constructor(
        address _governor,
        address _losslessGovernance,
        address _arbitrableProxy,
        address _klerosLiquid
    ) {
        governor = _governor;
        losslessGovernance = LosslessGovernance(_losslessGovernance);
        arbitrableProxy = IArbitrableProxy(_arbitrableProxy);
        klerosLiquid = KlerosLiquid(_klerosLiquid);
    }

    modifier onlyGovernor() {
        require(
            msg.sender == governor,
            "Only the governor can call this function."
        );
        _;
    }

    function setGovernor(address _newGovernor) public onlyGovernor {
        governor = _newGovernor;
    }

    function setCourtID(uint256 _courtID) public onlyGovernor {
        courtID = _courtID;
    }

    function setNumberOfJurors(uint256 _numberOfJurors) public onlyGovernor {
        numberOfJurors = _numberOfJurors;
    }

    function setMetaevidenceURI(
        string memory _metaevidenceURI
    ) public onlyGovernor {
        metaevidenceURI = _metaevidenceURI;
    }

    //events
    event DisputeCreated(uint256 reportID, uint256 disputeID);
    event VoteExecuted(uint256 reportID);

    //view functions
    function getDisputeID(uint256 _reportID) public view returns (uint256) {
        return reportIDToDisputeID[_reportID];
    }

    function getGovernor() public view returns (address) {
        return governor;
    }

    function getLosslessGovernance() public view returns (LosslessGovernance) {
        return losslessGovernance;
    }

    function getArbitrableProxy() public view returns (IArbitrableProxy) {
        return arbitrableProxy;
    }

    function getKlerosLiquid() public view returns (KlerosLiquid) {
        return klerosLiquid;
    }

    function getCourtID() public view returns (uint256) {
        return courtID;
    }

    function getNumberOfJurors() public view returns (uint256) {
        return numberOfJurors;
    }

    function getMetaevidenceURI() public view returns (string memory) {
        return metaevidenceURI;
    }

    function isReportExecuted(uint256 _reportID) public view returns (bool) {
        return executedReports[_reportID];
    }

    //write functions
    function invokeVote(uint256 _reportID) public payable {
        require(
            reportIDToDisputeID[_reportID] == 0,
            "Dispute already created for this report."
        );

        bytes memory extraData = abi.encodePacked(courtID, numberOfJurors);

        uint256 disputeID = arbitrableProxy.createDispute{
            value: arbitrationCost
        }(extraData, metaevidenceURI, 2);

        emit DisputeCreated(_reportID, disputeID);

        reportIDToDisputeID[_reportID] = disputeID;

        //Refund extra amounts beyond the arbitration cost.
        uint256 arbitrationCost = klerosLiquid.arbitrationCost(extraData);
        if (msg.value > arbitrationCost) {
            payable(msg.sender).transfer(msg.value - arbitrationCost);
        }
    }

    function executeVote(uint256 _reportID) public {
        require(!executedReports[_reportID], "Report already executed.");

        uint256 disputeID = reportIDToDisputeID[_reportID];
        require(disputeID != 0, "Dispute not found for this report.");

        //Polls for the provisional results of the first round of the arbitration case
        (
            uint256 winningChoice,
            uint256[] memory counts,
            bool tied
        ) = klerosLiquid.getVoteCounter(disputeID, 0);

        require(
            winningChoice == 1 && !tied && counts[1] == numberOfJurors,
            "Invocation criteria not fulfilled."
        );

        executedReports[_reportID] = true;
        losslessGovernance.tokenOwnersVote(_reportID, true);
        emit VoteExecuted(_reportID);
    }
}
