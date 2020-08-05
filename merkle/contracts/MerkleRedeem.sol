pragma solidity 0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import "./IERC20.sol";

contract MerkleRedeem {

  IERC20 public token;
  address public owner;

  event Claimed(address _claimant, uint256 _balance);


  // Recorded weeks
  uint latestWeek;
  mapping(uint => bytes32) public weekMerkleRoots;
  mapping(uint => uint) public weekTimestamps;
  mapping(uint => bytes32) public weekBlockHashes;

  mapping(uint => mapping(address => bool)) claimed;

  constructor(
    address _token
  ) public {
    token = IERC20(_token);
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "Must be the contract owner");
    _;
  }

  modifier requireWeekInPast(uint week) {
    require(week <= latestWeek, "Week cannot be in the future");
    _;
  }

  modifier requireWeekRecorded(uint _week) {
    require(weekTimestamps[_week] != 0);
    require(weekBlockHashes[_week] != 0);
    _;
  }

  function disburse(address _liquidityProvider, uint _balance) private {
    if (_balance > 0) {
      token.transfer(_liquidityProvider, _balance);
      emit Claimed(_liquidityProvider, _balance);
    } else {
      revert('No balance would be transfered - not gonna waste your gas');
    }
  }


  function offsetRequirementMet(address user, uint _week) view public returns (bool){
      bytes32 blockHash = weekBlockHashes[_week];
      uint timestamp = weekTimestamps[_week];
      uint offsetSeconds = userWeekOffset(user, blockHash);

      uint earliestClaimableTimestamp = timestamp + offsetSeconds;
      return earliestClaimableTimestamp < block.timestamp;
  }

  function claimWeek(uint _week, uint _claimedBalance, bytes32[] memory _merkleProof) public
  requireWeekInPast(_week)
  requireWeekRecorded(_week)
  {
    // if trying to claim for the current week
    if(_week == latestWeek) {
      require(offsetRequirementMet(msg.sender, latestWeek), "It is too early to claim for the current week");
    }

    require(!claimed[_week][msg.sender]);
    require(verifyClaim(msg.sender, _week, _claimedBalance, _merkleProof), 'Incorrect merkle proof');

    disburse(msg.sender, _claimedBalance);
    claimed[_week][msg.sender] = true;
  }

  struct Claim {
    uint week;
    uint balance;
    bytes32[] merkleProof;

  }

  function claimWeeks(Claim[] memory claims) public
  {
    uint totalBalance = 0;
    Claim memory claim ;
    for(uint i = 0; i < claims.length; i++) {
      claim = claims[i];
      require(claim.week <= latestWeek, "Week cannot be in the future");
      require(weekTimestamps[claim.week] != 0);
      require(weekBlockHashes[claim.week] != 0);

      // if trying to claim for the current week
      if(claim.week == latestWeek) {
        require(offsetRequirementMet(msg.sender, latestWeek), "It is too early to claim for the current week");
      }

      require(!claimed[claim.week][msg.sender]);
      require(verifyClaim(msg.sender, claim.week, claim.balance, claim.merkleProof), 'Incorrect merkle proof');

      totalBalance += claim.balance;
      claimed[claim.week][msg.sender] = true;
    }
    disburse(msg.sender, totalBalance);
  }

  function verifyClaim(address _liquidityProvider, uint _week, uint _claimedBalance, bytes32[] memory _merkleProof) view public returns (bool valid) {
    bytes32 leaf = keccak256(abi.encodePacked(_liquidityProvider, _claimedBalance));
    return MerkleProof.verify(_merkleProof, weekMerkleRoots[_week], leaf);
  }

  function userWeekOffset(address _liquidityProvider, bytes32 _weekBlockHash) pure public returns (uint offset) {
    bytes32 hash = keccak256(abi.encodePacked(_liquidityProvider, _weekBlockHash));
    assembly {
      offset :=
        mod(
          hash,
          604800 // seconds in a week
        )
    }
    return offset;
  }


  function finishWeek(uint _week, uint _timestamp, bytes32 _blockHash) public
  onlyOwner
  {
    weekTimestamps[_week] = _timestamp;
    weekBlockHashes[_week] = _blockHash;
    if (_week > latestWeek) { // just in case we get these out of order
      latestWeek = _week;
    }
  }

  function seedAllocations(uint _week, bytes32 _merkleRoot) external
  requireWeekRecorded(_week)
  onlyOwner
  {
    require(weekMerkleRoots[_week] == bytes32(0), "cannot rewrite merkle root");
    weekMerkleRoots[_week] = _merkleRoot;
  }
}