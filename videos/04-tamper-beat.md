# 04 · The tamper beat: proving the ledger is not editable — 3 min

**Prep:**
- Studio running with a populated ledger (run `pnpm demo:reset` first, then process at least one draw so there are 5+ receipts)
- Terminal open with `jq` installed and available
- Text editor open, ready to edit `.unykorn/receipts.jsonl`
- Everything on one screen — this beat is the reveal, no context-switching

## Cold open (0:00 – 0:15)

> "This is the ninety-second beat that lands the whole pitch. Every claim we've made about audit trails becomes concrete in the next three interactions."

*Screen: Studio's Receipts tab visible, showing a populated hash-chained ledger.*

## Beat 1: prove the chain is valid (0:15 – 0:45)

> "First — the chain is valid right now. Curl the receipts endpoint, pipe to jq, look at verification."

```
curl -s http://localhost:3200/api/receipts | jq .verification
```

*Screen: run the curl. Output shows:*

```
{
  "valid": true,
  "brokenAtSeq": null,
  "reason": null
}
```

> "Valid true. No broken sequence. No reason for concern. This is what the ledger looks like when nothing has been tampered with."

## Beat 2: tamper with a receipt (0:45 – 1:45)

> "Now I'm going to break it. Open the ledger file — it's a plain JSONL, one receipt per line, human-readable."

*Screen: open `.unykorn/receipts.jsonl` in a text editor. Show the receipts, all one-line JSON, hash-chained.*

> "Pick any receipt. I'll edit the title of receipt three — the deploy of DrawEscrow. Change one character in the title. Save."

*Screen: change 'Deploy DrawEscrow' to something like 'Depioy DrawEscrow' — a single-character typo. Save.*

> "Now re-run the curl."

```
curl -s http://localhost:3200/api/receipts | jq .verification
```

*Screen: run the curl. Output shows:*

```
{
  "valid": false,
  "brokenAtSeq": 3,
  "reason": "content tampered"
}
```

> "The chain immediately reports which receipt was tampered — seq three — and what specifically broke — content tampered. Because every receipt's hash is computed over its own content plus the previous receipt's hash, changing any past field breaks the whole chain from that point forward. There is no way to edit a receipt after the fact without producing exactly this signal."

## Beat 3: restore and verify (1:45 – 2:30)

> "Restore in three seconds."

*Screen: run:*

```
pnpm demo:reset
```

*Screen: reset output flies by. Studio still open. Curl again:*

```
curl -s http://localhost:3200/api/receipts | jq .verification
```

*Screen:*

```
{
  "valid": true,
  "brokenAtSeq": null,
  "reason": null
}
```

> "Fresh from genesis. Every receipt regenerated, every hash freshly computed, every prevHash correctly linked. This is the state the demo lives in."

## Close (2:30 – 3:00)

> "That's it. Three commands. What counsel sees is exactly this — a chain that reports itself valid, breaks visibly when tampered with, and restores from a single command. No mystical infrastructure, no black-box service, no trust required in Unykorn as a company. The ledger is a plain file. The verifier is a curl to a documented endpoint. The tamper signal is a specific reason string naming the broken sequence number."

> "This is what makes the whole audit-trail claim real rather than aspirational. Every other video in this series shows what gets written to the chain. This one shows why writing to the chain matters."

**End card:** "smart-contract-builder — 04 tamper beat — playlist ends"

## Recording notes

- Do not rehearse the tamper step so many times that the muscle memory makes it look effortless. It's supposed to feel deliberate. One or two seconds of visible cursor movement between the edit and the save is fine — it makes it clear you're actually editing a file, not running a pre-scripted macro.
- Do not use a fake ledger for this. Run `pnpm demo:reset` fresh before recording. If you edit a fabricated JSONL, someone in the audience notices and the entire beat collapses.
- The final curl after restore is the reveal. Give it two full seconds on screen before speaking the close.
