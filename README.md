# Slots [B42]

The Build 42 version of Slots, based on the latest published B41 release.

- [Steam Workshop release](https://steamcommunity.com/sharedfiles/filedetails/?id=3827350632)
- Workshop ID: `3827350632`
- Mod ID: `SlotsB42`
- Game version tested: `42.21.0` (single-player)
- Current currency: vanilla `Base.Money`

This `b42` branch is the place to work on the new version. The existing `main`
branch contains the older B41 source.

## Play locally

1. Copy `Contents/mods/SlotsB42` into your `Zomboid/mods` folder.
2. Enable SlotsB42 and restart the game. Avoid loading a second local/Workshop
   copy of the same mod, and do not enable the B41 Slots mod with it.
3. Carry Base.Money, right-click a green Dr. Oids arcade machine, and choose
   **Play Slots**.

The five bets are $5, $15, $50, $75 and $100. Odds, weighted results and jackpots
match the published B41 release. Reels stop separately, then show the payout
before the slot window counts up the winnings. Sound effects can be toggled.
Inventory settles immediately on the server; the delay is in the slot display.

## Working together

Marsu can use this branch for the economy and Computer RP integration. Exact
dependencies and server versions still need to be confirmed. Start with
[the integration handoff](integration/MOD-VERSIONS.md).

The repository link provides read access. Direct pushes and GitHub's upload/edit
controls require an accepted collaborator invitation. Send the owner your GitHub
username to arrange access. Anyone can also fork the public repository and open
a pull request targeting **`b42`**.

For changes, start a branch from `b42`, make a commit, and open a pull request
with **base: b42**. If using the GitHub website, switch to `b42` before uploading
files, then choose the option to create a new branch and pull request. Keep
integration notes in `integration/`; put working mod changes under `Contents/`.

```sh
git clone --branch b42 https://github.com/ObsidixEntertainment/SlotsMod.git
cd SlotsMod
git switch -c economy-integration
```

## Code locations

| File | Purpose |
| --- | --- |
| `Contents/mods/SlotsB42/42/media/lua/client/slots.lua` | Window, reel animation, cues and result display |
| `Contents/mods/SlotsB42/42/media/lua/server/slotsserver.lua` | Validation, roll, wager debit, payout and request replay protection |
| `Contents/mods/SlotsB42/42/media/lua/shared/slotsshared.lua` | Bet tiers, payout tables, machine detection and cash lookup |
| `Contents/mods/SlotsB42/42/media/scripts/` | Current and legacy item definitions |

There is no PhunMart/PhunMarket, Bikini Tools or Computer RP integration yet.
Keep the server responsible for money when adding an economy adapter. Duplicate
requests must return the existing result without charging or paying again.
Closing the window must not undo a completed settlement.

## Tests

Use Python 3.12 with the test dependency in a virtual environment:

```sh
python -m venv .venv
# Windows PowerShell: .\.venv\Scripts\Activate.ps1
# Linux/macOS: source .venv/bin/activate
python -m pip install -r requirements-test.txt
python tests/test_port.py
```

The 13 regression groups run under Lua 5.1 using PZ boundary doubles. They cover
10,000 seeded outcomes against the published B41 reference, money settlement,
request replays, invalid bets, timeouts, closing/death, and reveal/sound timing.
They do not replace an actual multiplayer test. All five wagers, item loading,
inventory changes and presentation were also checked in a copied save on 42.21.0.

## Workshop packaging

The uploader folder contains `Contents/`, `preview.png` and `workshop.txt`.
Only `Contents/` is mod payload. Tests, integration notes and documentation stay
outside it. `workshop.txt` points to the existing B42 release; keep that ID when
updating the release. Publishing remains a separate manual step by the owner.

The B41 test reference comes from Workshop item `3726432478`, content manifest
`7108475017265074875`, updated 25 May 2026. Those reference files are fixtures,
not code to install with B42.
