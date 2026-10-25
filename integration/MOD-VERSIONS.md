# Economy / Computer RP integration handoff

Fill this in with the exact versions currently used on the server. This is the
starting point for adapting SlotsB42; the current release still uses Base.Money.

## Server and dependencies

Server Project Zomboid build: **pending**

| Component | Workshop link / ID | Mod ID from mod.info | Version, update date or commit | Notes |
| --- | --- | --- | --- | --- |
| PhunMart / PhunMarket (confirm exact mod) | Pending | Pending | Pending | Economy/shop dependency |
| Computer RP base mod | Pending | Pending | Pending | Confirm exact base mod |
| Marsu's computer/economy addon | Pending | Pending | Pending | Current integration source |
| Vending machine integration | Pending | Pending | Pending | Separate mod or part of addon? |
| Other required dependencies | Pending | Pending | Pending | Add one row per dependency |

If a mod has no version field, record its Workshop update date and the hash of
the exact source file(s) being integrated. Note any local edits applied on the
server, since they may differ from the Workshop download.

## Economy interface to confirm

- Currency/account identifier and whether the balance is per character or player.
- Server-side calls to read the balance, debit a wager and credit a payout.
- How each call reports success/failure, including insufficient funds.
- Whether debit/credit calls support transaction IDs or other replay protection.
- How the balance is synchronized with clients and the computer/vending UI.
- Whether casino ownership, claims and commissions belong in this first port.

## Files to contribute

Commit the relevant addon/adapter source you maintain, or link the upstream
repository and exact revision. For third-party dependencies, use the links and
version records above rather than copying whole Workshop folders into this repo.

Make a branch from `b42` and open a pull request targeting `b42`. Explain which
dependency versions you tested and how to reproduce the integration locally.

## Checks before publishing an economy integration

- Correct balance after wins, losses, insufficient funds and failed transactions.
- One debit and at most one payout when a request is retried.
- Closing the window or disconnecting does not lose or duplicate a settlement.
- Two players using a machine do not affect each other's accounts.
- Payout appears before the slot window displays the winnings.
- Live multiplayer testing against the dependency versions recorded above.
