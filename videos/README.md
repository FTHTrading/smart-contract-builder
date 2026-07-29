# Video Scripts

This folder contains scripts, storyboards, and recording notes for the Unykorn Studio explainer video series. **Nothing here is a rendered video** — these are the source assets for a video producer (you, an internal team member, or a contracted editor) to record.

## Production stack (recommended)

- **Screen recording**: OBS Studio (free, open source, works on Windows / macOS / Linux)
- **Simpler alternative**: Loom (browser-based, one-click share links, up to 5 min free tier)
- **Editing**: DaVinci Resolve free tier, or CapCut for something lighter
- **Voiceover**: any USB condenser mic (Blue Yeti, Shure MV7); record in a small closet for dead-room acoustics
- **Publishing**: YouTube unlisted → embed via `<iframe>` in the catalog site, or use a self-hosted `<video>` tag if you want no third-party analytics

## Script structure

Each script file follows this pattern:

```
# Title — <duration target>

## Cold open (0:00 – 0:15)
The single most important sentence, said before the intro plays.

## Slide 1 — <heading> (0:15 – X:XX)
> Narrator: "…"
*Screen: [what appears on screen]*
*Notes: [any technical prep — Anvil running, ledger reset, browser tab open]*

## Slide 2 …
```

Read the script cold, out loud, at least twice before recording. Anywhere you stumble is a phrasing bug; fix it before you hit record.

## The five scripts

| # | Title | Duration | Audience |
| --- | --- | --- | --- |
| [00](./00-overview.md) | Overview: what this library is and isn't | 4 min | Anyone landing on the repo |
| [01](./01-draw-escrow.md) | Draw Escrow: the M Helen use case | 7 min | Lender's counsel, sponsor's ops person |
| [02](./02-permissioned-security.md) | Permissioned Securities: ERC-3643 without T-REX complexity | 6 min | Engineering leaders, compliance-adjacent devs |
| [03](./03-carbon-portfolio.md) | Carbon Portfolio: subprocess bridge as abstraction test | 5 min | Investors, ESG leads |
| [04](./04-tamper-beat.md) | The tamper beat: proving the ledger is not editable | 3 min | Counsel, auditors |

## Publishing checklist per video

- [ ] Script rehearsed twice, cold read
- [ ] Screen recording set to 1920×1080 or higher
- [ ] Anvil + Studio + ledger in the exact state the script assumes (see per-video "prep" section)
- [ ] Voiceover clean, no ums or filler
- [ ] Cuts are hard cuts (no dissolves for a technical explainer — it dates the video)
- [ ] Captions burned in or as sidecar .vtt file (accessibility + LinkedIn autoplay)
- [ ] Video uploaded unlisted to YouTube first, share link circulated for review before going public
- [ ] `<iframe>` embed added to `docs/index.html`'s "Videos" section with a thumbnail
- [ ] Video title and description use the exact same words as the catalog site so search-to-video journeys work
