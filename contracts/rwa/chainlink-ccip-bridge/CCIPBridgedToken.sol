// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// Minimal CCIP types + interfaces. Chainlink's full CCIP contracts are ~30
/// files; we inline only what a token needs for burn-and-mint cross-chain
/// transfers so the audit surface stays small.
///
/// If a production deployment needs the full CCIP contract set (rate-limited
/// pools, allowlisted senders, receiver dispatchers), vendor the official
/// contracts from github.com/smartcontractkit/ccip. This template is the
/// minimum viable shape.

interface IRouterClient {
    struct EVMTokenAmount { address token; uint256 amount; }
    struct EVM2AnyMessage {
        bytes receiver;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        address feeToken;
        bytes extraArgs;
    }
    function ccipSend(uint64 destinationChainSelector, EVM2AnyMessage calldata message)
        external payable returns (bytes32 messageId);
    function getFee(uint64 destinationChainSelector, EVM2AnyMessage calldata message)
        external view returns (uint256 fee);
}

interface IAny2EVMMessageReceiver {
    struct Any2EVMMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        bytes sender;
        bytes data;
        IRouterClient.EVMTokenAmount[] destTokenAmounts;
    }
    function ccipReceive(Any2EVMMessage calldata message) external;
}

/// @title CCIPBridgedToken
/// @notice ERC-20 that moves across chains via Chainlink CCIP burn-and-mint.
///         Zero liquidity-pool risk (no honey-pot to drain). Unified supply
///         across every chain — every mint on a destination chain corresponds
///         one-to-one to a burn on the source chain.
///
///         Integration pattern:
///           1. Deploy CCIPBridgedToken on each chain the token should live on.
///           2. Whitelist each deployment's address as a peer via `setPeer`.
///           3. User calls `bridgeTo(destChainSelector, receiver, amount)` on
///              their local chain. Contract burns the amount + calls CCIP router.
///           4. On the destination chain, the CCIP router calls `ccipReceive`
///              on the destination CCIPBridgedToken, which mints to the receiver.
///
///         Peer whitelisting means only trusted deployments can trigger mints
///         on this contract — random senders cannot forge cross-chain messages.
contract CCIPBridgedToken is ERC20, AccessControl, IAny2EVMMessageReceiver {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IRouterClient public immutable ccipRouter;

    /// destinationChainSelector → this token's peer address on that chain
    mapping(uint64 => address) public peer;

    event PeerSet(uint64 indexed chainSelector, address peer);
    event BridgeOut(bytes32 indexed messageId, uint64 destChainSelector, address indexed from, bytes receiver, uint256 amount);
    event BridgeIn(bytes32 indexed messageId, uint64 sourceChainSelector, address indexed to, uint256 amount);

    error OnlyRouter();
    error UnknownPeer(uint64 chainSelector);
    error PeerMismatch(uint64 chainSelector, address expected, address got);
    error InsufficientBalance(uint256 requested, uint256 available);
    error InsufficientFee(uint256 required, uint256 sent);

    constructor(string memory name_, string memory symbol_, address admin, address router)
        ERC20(name_, symbol_)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        ccipRouter = IRouterClient(router);
    }

    function setPeer(uint64 chainSelector, address peerAddress) external onlyRole(ADMIN_ROLE) {
        peer[chainSelector] = peerAddress;
        emit PeerSet(chainSelector, peerAddress);
    }

    /// @notice Mint tokens locally. Only admin — this is bootstrap issuance,
    ///         separate from cross-chain movement (which is burn-and-mint).
    function mint(address to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        _mint(to, amount);
    }

    /// @notice Send tokens to a destination chain via CCIP.
    ///         User must approve this contract for `amount` first if they don't
    ///         hold as msg.sender (they should — this is called from EOA typically).
    ///         The native-currency fee for CCIP must be sent as msg.value.
    function bridgeTo(
        uint64 destChainSelector,
        bytes calldata receiver,
        uint256 amount
    ) external payable returns (bytes32 messageId) {
        address destPeer = peer[destChainSelector];
        if (destPeer == address(0)) revert UnknownPeer(destChainSelector);
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance(amount, balanceOf(msg.sender));

        // Burn locally first — CCIP-CCT (Cross-Chain Token) burn-and-mint semantics.
        _burn(msg.sender, amount);

        // Encode the mint instruction. The destination peer's ccipReceive will
        // decode this to know who to mint to and how much.
        bytes memory data = abi.encode(receiver, amount);

        IRouterClient.EVMTokenAmount[] memory tokenAmounts = new IRouterClient.EVMTokenAmount[](0);
        IRouterClient.EVM2AnyMessage memory message = IRouterClient.EVM2AnyMessage({
            receiver: abi.encode(destPeer),
            data: data,
            tokenAmounts: tokenAmounts,
            feeToken: address(0), // native gas fee
            extraArgs: ""
        });

        uint256 fee = ccipRouter.getFee(destChainSelector, message);
        if (msg.value < fee) revert InsufficientFee(fee, msg.value);

        messageId = ccipRouter.ccipSend{ value: fee }(destChainSelector, message);
        emit BridgeOut(messageId, destChainSelector, msg.sender, receiver, amount);

        // Refund excess.
        if (msg.value > fee) {
            (bool ok, ) = msg.sender.call{ value: msg.value - fee }("");
            require(ok, "refund failed");
        }
    }

    /// @notice Handler for inbound CCIP messages. Only the CCIP router can
    ///         call this; the message must have been sent by our peer on the
    ///         source chain (checked via peer whitelist).
    function ccipReceive(Any2EVMMessage calldata message) external override {
        if (msg.sender != address(ccipRouter)) revert OnlyRouter();
        address expectedPeer = peer[message.sourceChainSelector];
        if (expectedPeer == address(0)) revert UnknownPeer(message.sourceChainSelector);
        address actualSender = abi.decode(message.sender, (address));
        if (actualSender != expectedPeer) revert PeerMismatch(message.sourceChainSelector, expectedPeer, actualSender);

        (bytes memory receiverBytes, uint256 amount) = abi.decode(message.data, (bytes, uint256));
        address receiver = abi.decode(receiverBytes, (address));

        _mint(receiver, amount);
        emit BridgeIn(message.messageId, message.sourceChainSelector, receiver, amount);
    }

    receive() external payable {}
}
