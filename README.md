<p align="center"><img src="docs/images/icon.png" width="120" alt="Nunsseop icon"></p>

<h1 align="center">Nunsseop</h1>

<p align="center">
  <b>Your MacBook notch, finally useful.</b><br>
  Music, files, quick search, AI usage, your calendar and system HUDs, one hover away.
</p>

<p align="center">
  <a href="https://github.com/namekun/Nunsseop/releases/latest"><img src="https://img.shields.io/github/v/release/namekun/Nunsseop?color=c86bfa&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-ff5f8f" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/Swift-native-orange?logo=swift&logoColor=white" alt="Native Swift">
</p>

<p align="center">
  <b>English</b> · <a href="README.ko.md">한국어</a> · <a href="https://namekun.github.io/Nunsseop/">Website</a>
</p>

<p align="center">
  <img src="docs/images/home.png" width="720" alt="Expanded notch with now playing and calendar">
</p>

*Nunsseop* (눈썹) is Korean for *eyebrow*, the little arch above your screen. It's free, open source, and has no account, subscription or tracking.

## Install in 30 seconds

```sh
brew install --cask namekun/tap/nunsseop
```

<details>
<summary>Prefer a download?</summary>

1. Grab `Nunsseop-<version>.dmg` from [Releases](https://github.com/namekun/Nunsseop/releases/latest).
2. Drag Nunsseop into Applications.
3. The app isn't notarized yet, so run this once before the first launch (Homebrew does it for you):

   ```sh
   xattr -dr com.apple.quarantine /Applications/Nunsseop.app
   ```

</details>

Needs macOS 14 Sonoma or later. Works on Apple silicon and Intel, and on screens without a notch.

## Your first minute

1. **Hover over the notch.** It opens. Move the pointer away and it tucks itself back.
2. **Play something** in Music, Spotify, YouTube Music or any browser. The notch picks it up, and the collapsed notch shows a tiny artwork and visualizer.
3. **Right-click the notch → Settings** to choose your tabs, their order, the pop-ups you want and the size.

There's no Dock icon. Nunsseop lives in the notch.

## A look inside

| | |
| :---: | :---: |
| <img src="docs/images/tab-search.png" alt="Quick search with a calculation"><br>**Quick search.** <kbd>⌃⌥Space</kbd> from anywhere: open apps, search the web, calculate. | <img src="docs/images/tab-ai.png" alt="AI usage for Claude Code and Codex"><br>**AI usage.** Claude Code and Codex limits, no login needed. |
| <img src="docs/images/shelf.png" alt="File shelf with AirDrop tile"><br>**Shelf.** Park files in the notch, or drop them on AirDrop. | <img src="docs/images/tab-timer.png" alt="Timer tab"><br>**Timer.** Countdown, Pomodoro and stopwatch. |
| <img src="docs/images/tab-tools.png" alt="Tools tab"><br>**Tools.** Audio output, mic mute, keep awake, screen recording. | <img src="docs/images/tab-system.png" alt="System tab with device batteries"><br>**System.** CPU, memory, disk, network and device batteries. |
| <img src="docs/images/tab-emoji.png" alt="Emoji picker"><br>**Emoji.** Every emoji, searchable, one click to copy. | <img src="docs/images/hud-headphones.png" alt="Headphone battery HUD"><br>**HUDs.** Volume, brightness, AirPods battery and more. |

## Everything it does

**🎵 Music**
- **Now playing from any app.** Music, Spotify, YouTube Music, and browsers like Safari, Chrome, Arc, Dia and Aside. Artwork, controls and a progress bar you can drag.
- **Synced lyrics** from [LRCLIB](https://lrclib.net), under the title or under the notch while you work.
- **Sneak peek.** When the track changes, the title slides out for a moment.

**🗂️ Get things done**
- **Shelf.** Drag files onto the notch and back out later. Screenshots and finished downloads can land there automatically.
- **Calendar and reminders.** Your week, today's events, and reminders you can tick off.
- **Quick search.** <kbd>⌃⌥Space</kbd> opens apps, searches the web, and works out sums like `12*(3+4)`.
- **Timer, clipboard history, notes and an emoji picker.** Clipboard history stays in memory and skips anything a password manager marks as secret.

**💻 Your Mac**
- **System HUDs.** Volume, brightness (including DDC external displays), keyboard backlight, charging, Caps Lock and AirPods battery appear in the notch. It can take over the volume and brightness keys so the system HUD stays away.
- **System stats and batteries.** CPU, memory, disk, network, plus your mouse, keyboard and trackpad, with a warning when one runs low.
- **Camera and mic indicator.** A dot on the notch while any app uses them.
- **Tools.** Switch audio output, mute the mic, keep the Mac awake, record the screen and eject drives.
- **Weather, downloads, mirror and Dock apps**, one hover away.

**🤖 For developers**
- **AI usage.** Claude Code and Codex limits with reset times, and Claude Code's token use over the last 5 hours and 7 days. Read from files those tools already keep on your Mac, so there's nothing to sign in to.
- **Claude Code notifications.** The notch tells you when Claude Code is waiting for you ([setup below](#claude-code-notifications)).

**🧩 Make it yours**
- Pick your tabs and their order, what the header and collapsed notch show, and which pop-ups you get. **Anything you turn off stops running.**
- Choose the display, size and hover delay, launch at login, and hide the notch while the lid is closed.
- Swipe down to open, up to close, sideways on Home to skip tracks.
- Speaks English, 한국어, 日本語, 简体中文, Español, Deutsch and Français, following your Mac.

## FAQ

<details>
<summary><b>macOS says Nunsseop can't be opened.</b></summary>

The app isn't notarized yet. Install with Homebrew, or run `xattr -dr com.apple.quarantine /Applications/Nunsseop.app` once.
</details>

<details>
<summary><b>Nothing shows up when I play music.</b></summary>

Nunsseop shows whatever macOS lists as Now Playing, so the player has to appear in Control Center. Most apps and browsers do. See [how now playing works](#how-now-playing-works) for the fallback.
</details>

<details>
<summary><b>There are too many tabs.</b></summary>

Right-click the notch → Settings → Notch, and switch off what you don't need. Turned-off features stop running entirely.
</details>

<details>
<summary><b>My Mac has no notch.</b></summary>

You get a small pill at the top centre of the screen that works the same way. Pick which display it uses in Settings.
</details>

<details>
<summary><b>Why does AI usage show old Claude limits?</b></summary>

Claude's 5-hour and weekly percentages come from the cache the [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) HUD writes while you use Claude Code in a terminal. The card shows when it was last updated. Token totals are always live.
</details>

<details>
<summary><b>Volume keys stopped showing Nunsseop's HUD after an update.</b></summary>

Builds are ad-hoc signed, so macOS can forget the Accessibility permission. Remove Nunsseop from System Settings → Privacy & Security → Accessibility, add it again, then restart Nunsseop.
</details>

## Claude Code notifications

Nunsseop listens on `127.0.0.1:47750` for notifications from tools on your Mac. Requests must carry the secret token stored in `~/Library/Application Support/Nunsseop/notify-token`.

Open Settings, press **Copy Claude Code hook command**, and add it to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "<paste the copied command here>" }] }
    ]
  }
}
```

Any script can do the same:

```sh
curl -X POST http://127.0.0.1:47750/notify \
  -H "Authorization: Bearer $(cat ~/Library/Application\ Support/Nunsseop/notify-token)" \
  -d '{"title": "Build", "message": "Finished in 42 s"}'
```

## Permissions

Nunsseop asks for a permission only when you first use the feature that needs it.

| Feature | Permission | When it is asked |
| --- | --- | --- |
| Calendar | Calendars | When you press *Allow Access* on the Home tab |
| Reminders | Reminders | When you press *Allow Reminders* on the Home tab |
| Mirror | Camera | When you press *Allow Camera* on the Mirror tab |
| Screen recording | Screen Recording | The first time you start a recording |
| Recording with sound | Microphone | The first time you record with microphone audio on |
| Taking over volume, brightness and keyboard backlight keys | Accessibility | When you turn the option on in Settings |
| Fallback now playing for Music, Spotify and browsers | Automation | Only if the MediaRemote helper is unavailable |
| Launch at login | Login Items | When you turn it on in Settings |

## Privacy

Nunsseop doesn't collect or send personal data. It goes online only to:

- check `api.github.com` for a newer release once a day (can be turned off);
- look up synced lyrics on `lrclib.net` (can be turned off);
- fetch weather from `open-meteo.com` for the city you enter (off until you enter one);
- download artwork over HTTPS from known music services, only when the MediaRemote helper is unavailable.

Everything else stays on your Mac. The notification server only accepts connections from this Mac. AI usage is read from local files. Recordings are saved next to your screenshots. The camera preview runs only while the Mirror tab is open and is never recorded. Clipboard history is cleared when Nunsseop quits.

## How now playing works

Since macOS 15.4, the private MediaRemote framework only answers processes signed by Apple. Nunsseop ships a small helper library (`Sources/NowPlayingHelper`) that runs inside the system's `/usr/bin/perl`, reads the Now Playing state, sends play, pause, skip and seek commands, and streams JSON lines back to the app.

This relies on private API, so a future macOS update may break it. If it does, Nunsseop falls back to AppleScript for Music and Spotify and to reading media tabs in browsers. That fallback needs *Allow JavaScript from Apple Events* turned on in each browser. Dia has no menu item for it, so Nunsseop offers to restart it with `--enable-applescript-javascript`.

## Build from source

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release      # build/Nunsseop.app
./scripts/make-dmg.sh            # build/Nunsseop-<version>.dmg
```

You need the Xcode command line tools with Swift 5.10 or later. `scripts/bundle.sh` builds the Swift package and wraps it in an ad-hoc signed app bundle.

## License

[MIT](LICENSE). Issues and pull requests are welcome.
