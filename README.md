# Open Anyway

A macOS menu bar app that finds Gatekeeper-blocked apps and opens them anyway — without the trip through **System Settings › Privacy & Security**.

If you build or run a lot of unsigned Mac apps, you know the loop: double-click, get told the app "cannot be opened because it is from an unidentified developer," open Settings, scroll to Security, find the *Open Anyway* button, authenticate, go back, launch again. This does that from the menu bar.

The padlock in the menu bar tells you at a glance whether anything is blocked. Open it and every blocked app is listed with a single **Open Anyway** button — the same decision the OS offers you, in one click instead of six.

```bash
brew install toshon-jennings/tap/open-anyway
```

Requires macOS 14+ on Apple silicon. Full [install and upgrade instructions](#install) below.

## What it does

- **Finds blocked apps on its own.** No need to remember which app you were trying to launch.
- **Shows where each app came from** — `Downloaded by Safari · Jun 1` — so the click is an informed one.
- **Drag and drop.** Drop any `.app` onto the menu bar icon to unblock it, including apps the scan doesn't cover.
- **Repairs damaged bundles.** An app whose signature no longer matches its contents fails to launch even with quarantine removed, reporting only that it "is damaged." Open Anyway detects that case and re-signs the bundle so it can run.
- **Launch at Login** toggle, and an escape hatch that opens the real Privacy & Security pane for anything it can't resolve.

## Requirements

- macOS 14 or later
- Apple silicon — `build.sh` targets `arm64-apple-macos14.0`. For an Intel or universal build, change `-target` (or pass both arches) in [`build.sh`](build.sh).

## Install

```bash
brew install toshon-jennings/tap/open-anyway
```

Then launch it — it's a menu bar app, so nothing appears in the Dock:

```bash
open "$(brew --prefix open-anyway)/Open Anyway.app"
```

To keep it in `/Applications`:

```bash
ln -s "$(brew --prefix open-anyway)/Open Anyway.app" /Applications
```

### Upgrading

```bash
brew upgrade toshon-jennings/tap/open-anyway
```

If it reports nothing to do, the tap's copy of the formula is stale — `brew update` first.

### Why it's a formula and not a cask

Casks download a prebuilt app, and anything downloaded gets the `com.apple.quarantine` attribute. This app is ad-hoc signed, so Gatekeeper would block the download — you'd need Open Anyway to open Open Anyway.

Installing as a formula compiles it on your machine instead. The result was never downloaded, so it carries no quarantine attribute and Gatekeeper never assesses it. (`spctl --assess` still rejects the bundle if you ask it directly. Nothing ever asks, which is exactly the mechanism this app is built on.)

The trade is that you need the Xcode Command Line Tools, and the build takes about 15 seconds.

## Build from source

```bash
./build.sh
```

That produces `build/Open Anyway.app`. There's no Xcode project — it's a single `swiftc` invocation over `Sources/`, plus an ad-hoc `codesign`. Then:

```bash
open "build/Open Anyway.app"
```

## Permissions

On first scan macOS will ask for access to your **Downloads** and **Desktop** folders. Those are protected locations, and the app scans them because that's where downloaded apps usually sit.

Two things worth knowing:

- **The prompt blocks the scan until you answer it.** The read syscall genuinely waits on your decision. Results from other folders still appear while it's pending — the scan walks one folder at a time specifically so a pending prompt can't stall everything — but the folder itself stays unread until you decide.
- **Declining is respected, and currently silent.** If you decline, the app keeps working but simply won't report anything in that folder. It does not yet tell you coverage was reduced.

Because the app is ad-hoc signed, its code identity changes on every rebuild, so macOS treats each build as a new app and asks again. A stable Developer ID signature would make it a one-time prompt.

## How it works

Detection is a two-stage scan, because the accurate check is far too slow to run on everything.

**Stage 1 — narrow the field.** Only apps carrying the `com.apple.quarantine` extended attribute can be blocked at all, and reading that attribute is a single syscall. On a typical machine this cuts ~200 apps down to a handful.

**Stage 2 — ask Gatekeeper.** For each survivor, run `spctl --assess --type execute`, which is the same question the OS asks itself at launch time.

Stage 2 is the authority, and that distinction matters more than it looks. The quarantine attribute's flag bits *appear* to encode the verdict — there's even a bit that flips once an app has been approved — but they don't reliably. Notarized, perfectly fine apps can carry the same bits as blocked ones, so deciding from flag bits alone reports apps as blocked when they aren't. The assessment is the only trustworthy answer.

`spctl` earns that trust by hashing the whole bundle, which is expensive — several seconds for a large app. Three things keep it usable:

- Assessments run concurrently, capped so a scan doesn't spawn a burst of processes all hashing at once.
- Results stream out as they land, so a small blocked app appears immediately instead of waiting on the largest bundle in the queue.
- Results are cached against bundle modification time plus the raw quarantine value — a rebuild moves the first, a re-download moves the second — so repeat scans are effectively free.

Together that took a serial ~35s scan down to roughly 12–18s cold and ~150ms warm.

**Unblocking** removes the quarantine attribute from the bundle, which is what actually clears the block — Gatekeeper only assesses files that carry it. If the bundle's seal is also broken, it re-signs before launching.

Scanned locations, one level deep: `/Applications`, `/Applications/Utilities`, `~/Applications`, `~/Downloads`, `~/Desktop`. Deep-walking a home directory would cost far more than it finds.

## A note on trust

This performs the same action as the *Open Anyway* button already in System Settings, and it can't approve anything macOS wouldn't let you approve yourself. It makes that decision faster, which cuts both ways: Gatekeeper exists for a reason, and the reason you were stopped is that macOS could not verify who wrote the software. Unblock things you have a reason to trust — something you built, or something from a source you know. **Convenience is the point; skipping the judgment isn't.**

## Known gaps

- Declining a folder prompt reduces coverage without telling you (see [Permissions](#permissions)).
- The build targets Apple silicon only.
- Ad-hoc signed, so macOS re-prompts for folder access after each rebuild.
- The origin URL of a download is deliberately not shown. It used to live in the quarantine record, but modern macOS no longer populates that field — it was empty for every row on the machine this was built against — so the app shows the downloading app and date instead.

## License

MIT — see [LICENSE](LICENSE).
