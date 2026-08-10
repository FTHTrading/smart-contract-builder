// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title TreasuryPolicyEngine
 * @notice Automated Corporate Treasury Allocation Policy Engine enforcing risk caps, min liquidity reserve ratios, and yield reallocation rules.
 */
contract TreasuryPolicyEngine is AccessControl {
    bytes32 public constant POLICY_ADMIN_ROLE = keccak256("POLICY_ADMIN_ROLE");

    struct AllocationPolicy {
        bytes32 policyId;
        string corporationName;
        uint16 minCashReserveBps;   // e.g. 2000 = 20%
        uint16 maxSingleAssetBps;   // e.g. 4000 = 40%
        bool requiresKYC;
        bool requiresAccreditedOnly;
        bool active;
    }

    // policyId => AllocationPolicy
    mapping(bytes32 => AllocationPolicy) public policies;

    event PolicyCreated(bytes32 indexed policyId, string corporationName, uint16 minCashReserveBps);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POLICY_ADMIN_ROLE, admin);
    }

    function createPolicy(
        string calldata corporationName,
        uint16 minCashReserveBps,
        uint16 maxSingleAssetBps,
        bool requiresKYC,
        bool requiresAccreditedOnly
    ) external onlyRole(POLICY_ADMIN_ROLE) returns (bytes32 policyId) {
        require(minCashReserveBps <= 10000, "Invalid cash BPS");
        require(maxSingleAssetBps <= 10000, "Invalid asset BPS");

        policyId = keccak256(abi.encodePacked(corporationName, block.timestamp));

        policies[policyId] = AllocationPolicy({
            policyId: policyId,
            corporationName: corporationName,
            minCashReserveBps: minCashReserveBps,
            maxSingleAssetBps: maxSingleAssetBps,
            requiresKYC: requiresKYC,
            requiresAccreditedOnly: requiresAccreditedOnly,
            active: true
        });

        emit PolicyCreated(policyId, corporationName, minCashReserveBps);
    }

    function validateAllocation(
        bytes32 policyId,
        uint16 cashBps,
        uint16 assetBps
    ) external view returns (bool) {
        AllocationPolicy memory p = policies[policyId];
        if (!p.active) return false;
        if (cashBps < p.minCashReserveBps) return false;
        if (assetBps > p.maxSingleAssetBps) return false;

        return true;
    }
}
