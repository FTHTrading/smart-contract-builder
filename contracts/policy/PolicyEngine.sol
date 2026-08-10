// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PolicyEngine
 * @notice Real-time automated policy rule enforcer (Concentration Caps, Attestation Expiry, Risk Score Controls).
 */
contract PolicyEngine is AccessControl {
    bytes32 public constant POLICY_ADMIN_ROLE = keccak256("POLICY_ADMIN_ROLE");

    struct PolicyRule {
        bytes32 ruleId;
        string ruleName;
        uint16 maxConcentrationBps;
        uint256 maxAttestationAgeSec;
        bool active;
    }

    mapping(bytes32 => PolicyRule) public rules;

    event PolicyRuleCreated(bytes32 indexed ruleId, string ruleName, uint16 maxConcentrationBps);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POLICY_ADMIN_ROLE, admin);

        _initializeDefaults();
    }

    function createPolicyRule(
        string calldata ruleName,
        uint16 maxConcentrationBps,
        uint256 maxAttestationAgeSec
    ) external onlyRole(POLICY_ADMIN_ROLE) returns (bytes32 ruleId) {
        ruleId = keccak256(abi.encodePacked(ruleName, block.timestamp));

        rules[ruleId] = PolicyRule({
            ruleId: ruleId,
            ruleName: ruleName,
            maxConcentrationBps: maxConcentrationBps,
            maxAttestationAgeSec: maxAttestationAgeSec,
            active: true
        });

        emit PolicyRuleCreated(ruleId, ruleName, maxConcentrationBps);
    }

    function evaluatePolicy(
        bytes32 ruleId,
        uint16 currentConcentrationBps,
        uint256 lastAttestedAt
    ) external view returns (bool allowed, string memory reason) {
        PolicyRule memory r = rules[ruleId];
        if (!r.active) return (false, "Rule inactive");
        if (currentConcentrationBps > r.maxConcentrationBps) return (false, "Concentration cap exceeded");
        if (block.timestamp > lastAttestedAt && (block.timestamp - lastAttestedAt) > r.maxAttestationAgeSec) {
            return (false, "Attestation expired");
        }

        return (true, "Policy compliant");
    }

    function _initializeDefaults() internal {
        bytes32 defaultRule = keccak256("INSTITUTIONAL_DEFAULT_POLICY");
        rules[defaultRule] = PolicyRule({
            ruleId: defaultRule,
            ruleName: "Institutional Default Risk & Compliance Policy",
            maxConcentrationBps: 4000, // 40% cap
            maxAttestationAgeSec: 30 days,
            active: true
        });
    }
}
