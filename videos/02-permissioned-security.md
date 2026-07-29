# 02 · Permissioned Securities: ERC-3643 without T-REX complexity — 6 min

**Prep:**
- Anvil running, Studio running
- Studio home page open, ready to click the Permissioned Security template
- Solidity files open in a second window: IdentityRegistry.sol, ClaimTopicsRegistry.sol, PermissionedToken.sol

## Cold open (0:00 – 0:20)

> "T-REX is six contracts, a compliance-module system, and a full identity portability layer via ONCHAINID. For a single-issuer SPV holding one class of equity, you don't need any of that. You need three contracts, and you need them small enough to actually audit."

*Screen: side-by-side diagram — Tokeny T-REX (6 boxes with arrows) vs this library (3 boxes).*

## Slide 1 — The three contracts (0:20 – 1:30)

> "IdentityRegistry — a mapping of investor address to a set of claim topic IDs they hold. Topic 1 is KYC. Topic 2 is accredited investor. Topic 3 might be US-jurisdiction, topic 4 might be non-US. A trusted issuer — typically the sponsor's KYC provider — is the only role that can register investors and grant claims."

> "ClaimTopicsRegistry — the list of topic IDs required to receive this specific token. Reg D 506(c) private placement? That's topics one and two. Reg S offshore? Topics one and four. Retail-permissioned utility token? Topic one alone. The list is admin-settable so you can tighten or loosen eligibility over the security's life."

> "PermissionedToken — an ERC-20 with a receiver-eligibility check on every transfer, including mint. The token's _update hook reads both registries and reverts if the recipient isn't registered or is missing any required claim."

*Screen: switch between the three .sol files, highlighting the key state variables on each.*

## Slide 2 — Why this shape (1:30 – 2:30)

> "Registries are separate contracts from the token because their lifecycles diverge. A registry can be redeployed without touching the token — useful when you change identity providers. Multiple tokens can share one identity registry — useful when the same investor base holds multiple issuances."

> "The token's transfer hook is the single insertion point for compliance logic. Add ModularCompliance later when you need per-jurisdiction holding limits, transfer restrictions during lockup, or maximum-holder-count-per-country rules. For a single-issuer SPV without any of that, ship the three."

> "Two features borrowed from T-REX because they're operationally load-bearing. freezeTokens lets an agent partially freeze a specific investor's balance without changing balanceOf — court orders or suspected fraud. forceTransfer lets an agent move tokens with a required reason string — key recovery when an investor loses access. Both are AccessControl-gated to AGENT_ROLE, not admin, so they're separately assignable."

*Screen: PermissionedToken.sol, scroll through freezeTokens and forceTransfer. Highlight the AGENT_ROLE modifier and the reason string in the event.*

## Slide 3 — Live demo: deploy and configure (2:30 – 4:30)

*Screen: switch to Studio, click the Permissioned Security Token template.*

> "Studio loads the plan. Nine steps. Write the three .sol files. Install vendored OpenZeppelin. Compile. Deploy the identity registry, deploy the claim topics registry, deploy the token — each is its own approval click, each writes its own receipt. Then a note step confirming the setup is complete."

> "Approve write:IdentityRegistry. Editor shows the file. Approve compile — you can see 30 vendored OZ files plus 3 user sources going into the input, one hash covering everything. Approve deploy on each of the three contracts. Each deploy receipt records constructor args, chain ID, genesis hash, and two integrity checks — runtimeMatchesCompile and creationMatchesCompile — that prove the deployed bytecode is the audited bytecode with the audited constructor arguments."

*Screen: click through the approvals. Watch the Agent Lane. Show one deploy receipt in the Receipts tab.*

## Slide 4 — What onboarding an investor looks like (4:30 – 5:20)

> "Now to add an investor. Off-camera I've KYC'd Alice via our compliance provider. On-chain I run three transactions."

*Screen: terminal or cast.*

```
cast send $IDENTITY_REGISTRY "registerInvestor(address)" $ALICE
cast send $IDENTITY_REGISTRY "addClaim(address,uint256)" $ALICE 1   # KYC
cast send $IDENTITY_REGISTRY "addClaim(address,uint256)" $ALICE 2   # accredited
```

> "Now the token contract will accept transfers to Alice. Any transfer to someone NOT registered — or registered but missing a required claim — reverts with ReceiverNotEligible."

*Screen: run a mint to a random address (fails with the specific error), then a mint to Alice (succeeds).*

## Close (5:20 – 6:00)

> "Three contracts, small enough to audit. Not the full T-REX suite. But the transfer-time compliance shape is identical — which means if the issuance grows into needing ModularCompliance, that contract slots in at the same seam without rewriting the token."

> "Next video is Carbon Portfolio Assessment. Same Studio, same audit chain, entirely different capability — no contracts of our own, it's a subprocess bridge to the UnyKorn Carbon engine. Proves that the platform generalizes."

**End card:** "smart-contract-builder — 02 permissioned securities — next: carbon portfolio"
