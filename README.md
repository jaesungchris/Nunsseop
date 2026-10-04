# Nunsseop

**Nunsseop** (눈썹, Korean for *eyebrow*) turns the MacBook notch into a small, useful space: what's playing, a file shelf, your calendar and system HUDs, all hanging from the top of the screen.

Website: https://namekun.github.io/Nunsseop/ · [한국어](#한국어)

<p align="center">
  <img src="docs/images/home.png" width="680" alt="Expanded notch with now playing and calendar">
</p>

## Features

- **Now playing.** Title, artist, artwork, progress and playback controls for any app that reports to macOS Now Playing: Music, Spotify, YouTube Music, and browsers such as Safari, Chrome, Arc, Dia and Aside. The collapsed notch grows a small artwork and visualizer tinted with the artwork's colour.
- **Sneak peek.** When the track or play state changes, the title appears under the notch for a few seconds (or always, if you prefer).
- **File shelf.** Drag files onto the notch to keep them, drag them back out when you need them. The shelf survives restarts.
- **Calendar.** A week strip and the selected day's events on the Home tab.
- **System HUDs.** Volume changes, power connected or disconnected, and headphone battery (left, right and case) appear in the notch. Optionally, Nunsseop can take over the volume and brightness keys so the system HUD no longer appears.
- **Settings.** Expanded size, collapsed width on screens without a notch, hover delay, sneak peek, launch at login and every HUD can be adjusted.
- **English and Korean.** The interface follows your macOS language.

Screens without a notch get a pill at the top centre instead.

<p align="center">
  <img src="docs/images/collapsed.png" width="420" alt="Collapsed notch while music plays">
  <img src="docs/images/hud-headphones.png" width="420" alt="Headphone battery HUD">
</p>

## Requirements

- macOS 14 Sonoma or later (tested on macOS 26)
- Xcode command line tools with Swift 5.10 or later to build

## Build and run

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release
open build/Nunsseop.app
```

`scripts/bundle.sh` builds the Swift package and wraps it in `build/Nunsseop.app` with an ad-hoc signature. Move the app to `/Applications` if you want to launch it at login.

The app has no Dock icon. Hover over the notch to open it; right-click it for Settings and Quit.

## Permissions

| Feature | Permission | When it is asked |
| --- | --- | --- |
| Calendar | Calendars | When you press *Allow Access* on the Home tab |
| Taking over volume/brightness keys | Accessibility | When you turn the option on in Settings |
| Fallback now playing for Music/Spotify/browsers | Automation | Only if the MediaRemote helper is unavailable |
| Launch at login | Login Items | When you turn it on in Settings |

Because builds are ad-hoc signed, macOS may forget the Accessibility permission after you rebuild.

## How now playing works

Since macOS 15.4, the private MediaRemote framework only answers processes signed by Apple. Nunsseop ships a small helper library (`Sources/NowPlayingHelper`) that runs inside the system's `/usr/bin/perl`, reads the Now Playing state and sends play/pause/next/previous commands, and streams JSON lines back to the app.

This relies on private API and on how macOS treats Apple-signed binaries, so a future macOS update may break it. When the helper is unavailable, Nunsseop falls back to AppleScript for Music and Spotify, and to reading media tabs in browsers. That fallback needs *Allow JavaScript from Apple Events* turned on in each browser (Dia has no menu item for it and must be started with `--enable-applescript-javascript`).

## Privacy

Nunsseop has no network features of its own. When the MediaRemote helper is unavailable it downloads artwork images over HTTPS from the image servers of known music and video services, and it does not collect or send any data.

## Credits

Inspired by [boring.notch](https://github.com/TheBoredTeam/boring.notch). Nunsseop is an independent implementation and contains no boring.notch code.

## License

[MIT](LICENSE)

---

## 한국어

**Nunsseop(눈썹)** 은 MacBook 노치를 쓸모 있는 공간으로 바꾸는 macOS 앱입니다.

- **지금 재생 중:** Music, Spotify, YouTube Music, 그리고 Safari·Chrome·Arc·Dia·Aside 같은 브라우저 재생을 노치에 표시하고 제어합니다.
- **미리보기:** 곡이나 재생 상태가 바뀌면 노치 아래에 제목이 잠깐 나옵니다.
- **파일 선반:** 노치에 파일을 끌어다 두고, 필요할 때 다시 끌어냅니다.
- **캘린더:** 홈 탭에 주간 날짜와 일정을 보여 줍니다.
- **시스템 HUD:** 볼륨, 전원 연결, 헤드폰 배터리를 노치에 표시합니다. 원하면 기본 볼륨·밝기 HUD를 대체합니다.
- **설정:** 크기, 열림 지연, 미리보기, 로그인 시 실행 등을 조절할 수 있습니다.
- **언어:** macOS 언어 설정에 따라 영어 또는 한국어로 표시됩니다.

빌드 방법과 필요한 권한은 위 영문 설명을 참고하세요. 재생 정보는 비공개 MediaRemote 프레임워크를 Apple 서명 `/usr/bin/perl` 안에서 호출해 읽기 때문에, 이후 macOS 업데이트에서 동작하지 않을 수 있습니다.
