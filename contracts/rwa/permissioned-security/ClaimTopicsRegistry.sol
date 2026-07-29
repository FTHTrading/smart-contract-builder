// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ClaimTopicsRegistry
/// @notice The set of claim topic IDs required to hold or receive the token.
///         Common patterns:
///           - [1] just KYC (retail-permissioned)
///           - [1, 2] KYC + accredited-investor (Reg D 506(c))
///           - [1, 2, 3] KYC + accredited + US-only jurisdiction (Reg D domestic)
///           - [1, 4] KYC + non-US jurisdiction (Reg S offshore)
contract ClaimTopicsRegistry is AccessControl {
    uint256[] private _topics;

    event ClaimTopicAdded(uint256 indexed topicId);
    event ClaimTopicRemoved(uint256 indexed topicId);

    constructor(address admin, uint256[] memory initialTopics) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        for (uint256 i = 0; i < initialTopics.length; i++) {
            _topics.push(initialTopics[i]);
            emit ClaimTopicAdded(initialTopics[i]);
        }
    }

    function addTopic(uint256 topicId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _topics.push(topicId);
        emit ClaimTopicAdded(topicId);
    }

    function removeTopic(uint256 topicId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _topics.length; i++) {
            if (_topics[i] == topicId) {
                _topics[i] = _topics[_topics.length - 1];
                _topics.pop();
                emit ClaimTopicRemoved(topicId);
                return;
            }
        }
    }

    function getRequiredTopics() external view returns (uint256[] memory) {
        return _topics;
    }
}
