# UsageBar

A macOS menu-bar app that shows how much of your Claude subscription quota is left,
so you don't have to keep checking `/usage` while you work.

```
✳ 5h 88% · wk 75% · F 81%
```

The three numbers are your 5-hour session window, your weekly all-models window, and
your weekly model-scoped window. The text turns orange past 75% and red past 90%.
Click it for reset countdowns, a 7-day token chart, and what the week would have cost
at pay-as-you-go API prices.

## Requirements

- macOS 14 or later
- A Claude subscription (Pro or Max)
- [Claude Code](https://claude.com/claude-code) installed — used to mint the token and,
  optionally, as the source of the 7-day history chart

## Install

```sh
git clone https://github.com/<you>/usagebar.git
cd usagebar
make install
```

That builds `UsageBar.app`, copies it to `/Applications`, and launches it. The menu-bar
item will read `✳ Connect` until you finish setup.

## Connecting your account

Click the menu-bar item and follow the two steps it shows:

1. Run `claude setup-token` in a terminal. This is Claude Code's official command for
   minting a long-lived token tied to your own subscription.
2. Paste the token into UsageBar and click **Connect**.

UsageBar verifies the token against the API before storing it, so a bad paste fails
immediately rather than leaving you with a silently broken app.

### About your token

The token is stored in your login Keychain under the service name `UsageBar`, and it is
the only credential the app touches. **UsageBar never reads credentials belonging to
other applications** and never transmits your token anywhere except `api.anthropic.com`.

To disconnect, use **Disconnect token…** in the panel's `⋯` menu, which deletes the
Keychain entry. To revoke the token itself, use your Anthropic account settings.

## What it reads

| Data | Source |
|---|---|
| Live quota percentages and reset times | `GET https://api.anthropic.com/api/oauth/usage`, authenticated with your token |
| 7-day token history and cost estimate | Your local Claude Code logs in `~/.claude/projects/**/*.jsonl` — read-only, never uploaded |

If you don't use Claude Code for day-to-day work, the quota gauges still work; the
history chart will just be empty.

Refresh is adaptive so the numbers track reality while you're actually burning quota:
a file watcher on `~/.claude/projects` triggers a refresh within a second or two of
Claude Code activity, polling runs every 10 seconds while you're active or near a limit,
and drops to every 60 seconds when idle.

## Caveats

**The usage endpoint is not a public, documented API.** It is the internal endpoint
Claude Code itself uses to render `/usage`. Anthropic can change or remove it without
notice, and if they do, this app will need updating. Treat UsageBar as a convenience,
not something to depend on.

The cost figure is an *estimate* of what your logged usage would have cost at published
API list prices. It is not a bill, it does not reflect what you actually pay for your
subscription, and models with no entry in the pricing table are counted in the token
chart but excluded from the cost line.

## Development

```sh
make test    # run the unit tests
make run     # run from source without bundling
make app     # build UsageBar.app without installing it
```

The code is split in two: `UsageBarCore` holds all the logic (API decoding, log
scanning, aggregation, pricing, formatting, refresh policy) and has no UI dependencies,
so it is covered by unit tests. `UsageBar` is a thin AppKit + SwiftUI shell over it.

If `make test` can't find XCTest, your `xcode-select` is pointing at CommandLineTools;
the Makefile already redirects to `/Applications/Xcode.app` when it exists.

## License

MIT
