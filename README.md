# PRBar

Tiny macOS menu extra that shows how many GitHub pull requests are open on the repos you care about.

Inspired by [CodexBar](https://github.com/steipete/codexbar), but it is a separate app. It talks to GitHub through the `gh` CLI already logged in on your Mac. No extra token is stored.

The bar is a compact run of counts in repo order, for example `19·10·7·16`. Hover for names. Open a repo in the menu to see every open PR.

## Install

macOS 14+, [Swift / Xcode CLT](https://developer.apple.com/xcode/), and [`gh`](https://cli.github.com/) (`brew install gh && gh auth login`). Private repos need `repo` scope.

```bash
curl -fsSL https://raw.githubusercontent.com/sburl/prBar/main/install.sh | bash
```

That clones, builds, and drops `~/Applications/PRBar.app` (no Dock icon). On first launch, **Repos…** opens so you can add repositories. **Open at Login** is in the menu.

From a checkout:

```bash
./scripts/run.sh
```

The CLI is named `prbar-cli` because macOS filesystems treat `prbar` and `PRBar` as the same file.

See [`config.example.json`](config.example.json) for the file format (`~/.config/prbar/config.json`).

## Features

- Pick any GitHub repos (`owner/name` or a github.com URL)
- Set a display name and two-letter abbreviation when adding; edit them later in the list
- Drag to reorder; add and remove from **Repos…** (⌘,)
- Dependabot PRs always show in each repo list, grouped under a **Dependabot** header at the bottom
- **Count Dependabot PRs** only changes the numbers in the menu bar, not the list
- Refresh defaults to every two minutes (one `gh pr list` per repo). **Refresh Every** in the menu can go to 1 / 2 / 5 / 15 / 30 minutes or manual-only; ⌘R always fetches now

## CLI

```bash
~/Applications/PRBar.app/Contents/MacOS/prbar-cli
~/Applications/PRBar.app/Contents/MacOS/prbar-cli --include-dependabot
~/Applications/PRBar.app/Contents/MacOS/prbar-cli --json
```

## Notes

Menu-bar apps do not inherit your shell `PATH`. PRBar looks for `gh` in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, then `PATH`.

`refreshInterval` in the config file is seconds. `0` means manual refresh only.

MIT licensed. Copyright BestPriceLC.
