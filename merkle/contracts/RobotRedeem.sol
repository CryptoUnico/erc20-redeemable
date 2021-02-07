// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RobotRedeem is Ownable {

    IERC20 public token;

    event Claimed(address _claimant, uint256 _balance);

    // Recorded Weeks
    mapping(uint => bytes32) public weekMerkleRoots;
    mapping(uint => mapping(address => bool)) public claimed;

    constructor(address _token) public {
        token = IERC20(_token);
    }

    function disburse(address _user, uint _balance) private {
        if (_balance > 0) {
            emit Claimed(_user, _balance);
            require(token.transfer(_user, _balance), "ERR_TRANSFER_FAILED");
        }
    }

    function claimWeek(
        address _user, 
        uint _week, 
        uint _claimedBalance, 
        bytes32[] memory _merkleProof
        ) public {
        require(!claimed[_week][_user]);
        require(verifyClaim(_user, _week, _claimedBalance, _merkleProof), 'Incorrect merkle proof');

        claimed[_week][_user] = true;
        disburse(_user, _claimedBalance);
    }

    struct Claim {
        uint week;
        uint balance;
        bytes32[] merkleProof;
    }

    function claimWeeks(address _user, Claim[] memory claims) public {
        uint totalBalance = 0;
        Claim memory claim ;
        for(uint i = 0; i < claims.length; i++) {
            claim = claims[i];

            require(!claimed[claim.week][_user]);
            require(verifyClaim(_user, claim.week, claim.balance, claim.merkleProof), 'Incorrect merkle proof');

            totalBalance += claim.balance;
            claimed[claim.week][_user] = true;
        }
        disburse(_user, totalBalance);
    }

    function claimStatus(address _user, uint _begin, uint _end) external view 
        returns (bool[] memory) {
            uint size = 1 + _end - _begin;
            bool[] memory arr = new bool[](size);
            for(uint i = 0; i < size; i++) {
                arr[i] = claimed[_begin + i][_user];
        }
        return arr;
    }

    function merkleRoots(uint _begin, uint _end) external view 
        returns (bytes32[] memory) {
        uint size = 1 + _end - _begin;
        bytes32[] memory arr = new bytes32[](size);
        for(uint i = 0; i < size; i++) {
            arr[i] = weekMerkleRoots[_begin + i];
        }
        return arr;
    }

    function verifyClaim(address _user, uint _week, uint _claimedBalance, bytes32[] memory _merkleProof) 
        public view returns (bool valid) {
            bytes32 leaf = keccak256(abi.encodePacked(_user, _claimedBalance));
            return MerkleProof.verify(_merkleProof, weekMerkleRoots[_week], leaf);
        }

    function seedAllocations(uint _week,bytes32 _merkleRoot, uint _totalAllocation) external onlyOwner {
        require(weekMerkleRoots[_week] == bytes32(0), "cannot rewrite merkle root");
        weekMerkleRoots[_week] = _merkleRoot;

        require(token.transferFrom(msg.sender, address(this), _totalAllocation), "ERR_TRANSFER_FAILED");
    }
}
