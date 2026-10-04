<p align="center"><img src="docs/images/icon.png" width="128" alt="Nunsseop icon"></p>

# Nunsseop

**Nunsseop** (눈썹, Korean for *eyebrow*) turns the MacBook notch into a small, useful space: what's playing, a file shelf, your calendar and system HUDs, all hanging from the top of the screen.

Website: https://namekun.github.io/Nunsseop/ · [한국어](#한국어)

<p align="center">
  <img src="docs/images/home.png" width="680" alt="Expanded notch with now playing and calendar">
</p>

## Features

- **Now playing.** Title, artist, artwork and playback controls for any app that reports to macOS Now Playing: Music, Spotify, YouTube Music, and browsers such as Safari, Chrome, Arc, Dia and Aside. Drag the progress bar to seek. The collapsed notch grows a small artwork and visualizer tinted with the artwork's colour.
- **Sneak peek.** When the track or play state changes, the title appears under the notch for a few seconds (or always, if you prefer).
- **File shelf.** Drag files onto the notch to keep them and drag them back out when you need them. Drop files on the AirDrop tile to send them, or share them from the context menu. The shelf survives restarts.
- **Calendar and reminders.** A week strip, the selected day's events and the reminders due by then, which you can tick off from the notch.
- **Mirror.** A quick look at yourself through the camera of your choice.
- **System HUDs.** Volume, brightness (built-in and DDC-capable external displays), keyboard backlight, power connected or disconnected, and headphone battery (left, right and case) appear in the notch. Nunsseop can take over the volume and brightness keys so the system HUD no longer appears.
- **Gestures.** Swipe down on the notch to open it, up to close it, and left or right on the Home tab to skip tracks.
- **Settings.** Which display to use, size, hover delay, sneak peek, launch at login, update checks and every HUD can be adjusted.
- **Seven languages.** English, Korean, Japanese, Simplified Chinese, Spanish, German and French, following your macOS language.

Screens without a notch get a pill at the top centre instead.

<p align="center">
  <img src="docs/images/shelf.png" width="680" alt="File shelf with the AirDrop tile">
</p>
<p align="center">
  <img src="docs/images/collapsed.png" width="300" alt="Collapsed notch while music plays">
  <img src="docs/images/hud-headphones.png" width="420" alt="Headphone battery HUD">
</p>

## Requirements

- macOS 14 Sonoma or later (tested on macOS 26)
- Xcode command line tools with Swift 5.10 or later to build

## Install

Download the latest `Nunsseop-<version>.dmg` from [Releases](https://github.com/namekun/Nunsseop/releases), open it and drag Nunsseop to Applications.

The app is not notarized, so macOS blocks the first launch. Remove the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/Nunsseop.app
```

The app has no Dock icon. Hover over the notch to open it; right-click it for Settings and Quit.

## Build from source

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release      # build/Nunsseop.app
./scripts/make-dmg.sh            # build/Nunsseop-<version>.dmg
```

`scripts/bundle.sh` builds the Swift package and wraps it in an app bundle with an ad-hoc signature.

## Permissions

| Feature | Permission | When it is asked |
| --- | --- | --- |
| Calendar | Calendars | When you press *Allow Access* on the Home tab |
| Reminders | Reminders | When you press *Allow Reminders* on the Home tab |
| Mirror | Camera | When you press *Allow Camera* on the Mirror tab |
| Taking over volume, brightness and keyboard backlight keys | Accessibility | When you turn the option on in Settings |
| Fallback now playing for Music/Spotify/browsers | Automation | Only if the MediaRemote helper is unavailable |
| Launch at login | Login Items | When you turn it on in Settings |

Because builds are ad-hoc signed, macOS may forget the Accessibility permission after you rebuild.

## How now playing works

Since macOS 15.4, the private MediaRemote framework only answers processes signed by Apple. Nunsseop ships a small helper library (`Sources/NowPlayingHelper`) that runs inside the system's `/usr/bin/perl`, reads the Now Playing state and sends play/pause/next/previous commands, and streams JSON lines back to the app.

This relies on private API and on how macOS treats Apple-signed binaries, so a future macOS update may break it. When the helper is unavailable, Nunsseop falls back to AppleScript for Music and Spotify, and to reading media tabs in browsers. That fallback needs *Allow JavaScript from Apple Events* turned on in each browser (Dia has no menu item for it and must be started with `--enable-applescript-javascript`).

## Privacy

Nunsseop does not collect or send any personal data. Its network use is limited to:

- checking `api.github.com` for a newer release once a day (can be turned off in Settings);
- downloading artwork over HTTPS from the image servers of known music and video services, only when the MediaRemote helper is unavailable.

The camera preview is shown only while the Mirror tab is open and is never recorded.

## License

[MIT](LICENSE)

---

## 한국어

**Nunsseop(눈썹)** 은 MacBook 노치를 쓸모 있는 공간으로 바꾸는 macOS 앱입니다.

- **지금 재생 중:** Music, Spotify, YouTube Music, 그리고 Safari·Chrome·Arc·Dia·Aside 같은 브라우저 재생을 노치에 표시하고 제어합니다. 진행바를 끌어 재생 위치를 옮길 수 있습니다.
- **미리보기:** 곡이나 재생 상태가 바뀌면 노치 아래에 제목이 잠깐 나옵니다.
- **파일 선반:** 노치에 파일을 끌어다 두고 필요할 때 다시 끌어냅니다. AirDrop 칸에 놓으면 바로 AirDrop으로 보내고, 우클릭으로 공유할 수 있습니다.
- **캘린더와 미리 알림:** 홈 탭에 주간 날짜, 일정, 미리 알림을 보여 주고 노치에서 바로 완료 처리합니다.
- **시스템 HUD:** 볼륨, 밝기(내장 화면과 DDC 지원 외부 모니터), 키보드 백라이트, 전원 연결, 헤드폰 배터리를 노치에 표시합니다. 원하면 기본 볼륨·밝기 HUD를 대체합니다.
- **미러:** 원하는 카메라로 내 모습을 바로 확인합니다.
- **제스처:** 노치에서 아래로 쓸면 열리고 위로 쓸면 닫히며, 홈 탭에서 좌우로 쓸면 곡이 넘어갑니다.
- **설정:** 표시할 화면, 크기, 열림 지연, 미리보기, 로그인 시 실행, 업데이트 확인 등을 조절할 수 있습니다.
- **언어:** 영어, 한국어, 일본어, 중국어(간체), 스페인어, 독일어, 프랑스어를 macOS 언어 설정에 따라 표시합니다.

설치는 [Releases](https://github.com/namekun/Nunsseop/releases)에서 dmg를 받아 응용 프로그램 폴더로 옮기면 됩니다. 공증되지 않은 앱이라 처음 한 번은 위의 `xattr` 명령으로 격리 표시를 지워야 합니다. 빌드 방법과 필요한 권한은 위 영문 설명을 참고하세요. 재생 정보는 비공개 MediaRemote 프레임워크를 Apple 서명 `/usr/bin/perl` 안에서 호출해 읽기 때문에, 이후 macOS 업데이트에서 동작하지 않을 수 있습니다.
