<p align="center"><img src="docs/images/icon.png" width="128" alt="Nunsseop 아이콘"></p>

# Nunsseop

[English](README.md) · **한국어** · [웹사이트](https://namekun.github.io/Nunsseop/)

**Nunsseop(눈썹)** 은 MacBook 노치를 쓸모 있는 공간으로 바꿔 줍니다. 지금 재생 중인 음악, 파일 선반, 캘린더, 시스템 HUD가 화면 맨 위에 매달려 있습니다.

<p align="center">
  <img src="docs/images/home.png" width="680" alt="음악과 캘린더가 보이는 펼친 노치">
</p>

## 기능

- **지금 재생 중.** macOS의 '지금 재생 중'에 정보를 보내는 모든 앱의 제목, 아티스트, 앨범아트와 재생 컨트롤을 보여 줍니다. Music, Spotify, YouTube Music, 그리고 Safari·Chrome·Arc·Dia·Aside 같은 브라우저도 됩니다. 진행바를 끌어 재생 위치를 옮길 수 있고, 접힌 노치에는 앨범아트 색을 입힌 작은 이퀄라이저가 붙습니다.
- **실시간 가사.** [LRCLIB](https://lrclib.net)에서 받은 현재 가사 줄을 제목 아래에, 또는 재생 중 노치 아래에 계속 보여 줍니다.
- **미리보기.** 곡이나 재생 상태가 바뀌면 노치 아래에 제목이 잠깐 나옵니다. 계속 보이게 할 수도 있습니다.
- **파일 선반.** 노치에 파일을 끌어다 두고 필요할 때 다시 끌어냅니다. AirDrop 칸에 놓으면 바로 AirDrop으로 보내고, 우클릭으로 공유할 수 있습니다. 앱을 다시 켜도 남아 있습니다.
- **캘린더와 미리 알림.** 주간 날짜, 선택한 날의 일정, 그날까지의 미리 알림을 보여 주고 노치에서 바로 완료 처리합니다.
- **타이머.** 카운트다운, 뽀모도로, 스톱워치. 접힌 노치에 남은 시간이 표시됩니다.
- **클립보드 기록.** 최근 복사한 텍스트를 검색하고 클릭 한 번으로 다시 복사합니다. 메모리에만 두며, 비밀번호 관리자가 숨김 표시한 항목은 저장하지 않습니다.
- **메모.** 마우스만 올리면 열리는 메모장입니다.
- **도구.** 오디오 출력 전환, 마이크 음소거, 잠자기 방지, 화면 녹화(접힌 노치에 녹화 시간 표시), 외장 드라이브 꺼내기.
- **시스템.** CPU, 메모리, 디스크, 네트워크를 한눈에. 마우스·키보드·트랙패드 배터리도 보여 주고, 부족하면 알려 줍니다.
- **빠른 검색.** 어디서든 ⌃⌥Space를 눌러 앱을 열고, 웹을 검색하고, `12*(3+4)` 같은 계산 결과를 바로 복사합니다.
- **AI 사용량.** Claude Code와 Codex의 사용 한도, Claude Code의 최근 5시간·7일 토큰 사용량을 보여 줍니다. 두 도구가 이 Mac에 이미 남기는 파일만 읽으므로 로그인하거나 설정할 것이 없습니다.
- **이모지 선택기.** 모든 이모지를 이름으로 검색하고, 최근에 쓴 이모지가 먼저 나옵니다. 클릭하면 복사됩니다.
- **개인정보 표시.** 어떤 앱이든 카메라나 마이크를 쓰는 동안 접힌 노치에 표시가 뜹니다.
- **앱.** Dock에 있는 앱을 노치에서 바로 실행합니다.
- **날씨.** 지정한 도시의 현재 날씨를 헤더에 보여 줍니다([Open-Meteo](https://open-meteo.com)).
- **다운로드.** 다운로드가 시작되고 끝나면 알려 주고, 원하면 선반에 넣어 줍니다.
- **미러.** 원하는 카메라로 내 모습을 바로 확인합니다.
- **시스템 HUD.** 볼륨, 밝기(내장 화면과 DDC를 지원하는 외부 모니터), 키보드 백라이트, 전원 연결, 배터리 부족·완충, Caps Lock, 헤드폰 배터리(왼쪽·오른쪽·케이스)를 노치에 표시합니다. 새 스크린샷은 자동으로 선반에 들어갑니다.
- **Claude Code 알림.** Claude Code(또는 로컬 스크립트)가 확인이 필요할 때 노치에 메시지를 띄웁니다. 아래 설명을 참고하세요. 원하면 볼륨·밝기 키를 가로채 기본 HUD 대신 노치에만 표시합니다.
- **제스처.** 노치에서 아래로 쓸면 열리고 위로 쓸면 닫히며, 홈 탭에서 좌우로 쓸면 곡이 넘어갑니다.
- **내 맞게 구성.** 어떤 탭을 어떤 순서로 보일지, 헤더와 접힌 노치에 무엇을 띄울지, 어떤 알림을 받을지 정할 수 있습니다. 꺼 둔 기능은 백그라운드에서도 동작하지 않습니다. 표시할 화면, 크기, 열림 지연, 로그인 시 실행, 업데이트 확인, 덮개를 닫았을 때(클램쉘) 표시 여부도 조절할 수 있습니다.
- **7개 언어.** 영어, 한국어, 일본어, 중국어(간체), 스페인어, 독일어, 프랑스어를 macOS 언어 설정에 따라 표시합니다.

노치가 없는 화면에서는 상단 중앙에 작은 막대로 나타납니다.

<p align="center">
  <img src="docs/images/shelf.png" width="680" alt="AirDrop 칸이 있는 파일 선반">
</p>
<p align="center">
  <img src="docs/images/collapsed.png" width="300" alt="재생 중일 때 접힌 노치">
  <img src="docs/images/hud-headphones.png" width="420" alt="헤드폰 배터리 HUD">
</p>

## 요구 사항

- macOS 14 Sonoma 이상 (macOS 26에서 테스트)
- 직접 빌드하려면 Swift 5.10 이상이 포함된 Xcode 명령줄 도구

## 설치

[Homebrew](https://brew.sh)로 설치:

```sh
brew install --cask namekun/tap/nunsseop
```

또는 [Releases](https://github.com/namekun/Nunsseop/releases)에서 최신 `Nunsseop-<버전>.dmg`를 받아 열고 Nunsseop을 응용 프로그램 폴더로 끌어다 놓으세요. 공증되지 않은 앱이라 처음 실행하기 전에 한 번 격리 표시를 지워야 합니다(Homebrew로 설치하면 자동으로 처리됩니다).

```sh
xattr -dr com.apple.quarantine /Applications/Nunsseop.app
```

Dock 아이콘은 없습니다. 노치에 마우스를 올리면 열리고, 우클릭하면 설정과 종료 메뉴가 나옵니다.

## 직접 빌드

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release      # build/Nunsseop.app
./scripts/make-dmg.sh            # build/Nunsseop-<버전>.dmg
```

`scripts/bundle.sh`는 Swift 패키지를 빌드해 임시 서명(ad-hoc)된 앱 번들로 묶습니다.

## Claude Code 알림

Nunsseop은 이 Mac 안(`127.0.0.1:47750`)에서만 다른 도구의 알림을 받습니다. 요청에는 `~/Library/Application Support/Nunsseop/notify-token`에 저장된 비밀 토큰이 있어야 합니다.

Claude Code가 입력을 기다릴 때마다 노치에 알림을 받으려면, Nunsseop 설정에서 **Claude Code 훅 명령 복사**를 누른 뒤 `~/.claude/settings.json`에 추가하세요.

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "<복사한 명령을 붙여 넣기>" }] }
    ]
  }
}
```

다른 스크립트에서도 같은 방식으로 보낼 수 있습니다.

```sh
curl -X POST http://127.0.0.1:47750/notify \
  -H "Authorization: Bearer $(cat ~/Library/Application\ Support/Nunsseop/notify-token)" \
  -d '{"title": "빌드", "message": "42초 만에 끝났습니다"}'
```

## 권한

| 기능 | 권한 | 요청 시점 |
| --- | --- | --- |
| 캘린더 | 캘린더 | 홈 탭에서 *접근 허용*을 누를 때 |
| 미리 알림 | 미리 알림 | 홈 탭에서 *미리 알림 허용*을 누를 때 |
| 미러 | 카메라 | 미러 탭에서 *카메라 허용*을 누를 때 |
| 볼륨·밝기·키보드 백라이트 키 가로채기 | 손쉬운 사용 | 설정에서 해당 옵션을 켤 때 |
| Music·Spotify·브라우저 대체 경로 | 자동화 | MediaRemote 헬퍼를 쓸 수 없을 때만 |
| 로그인 시 실행 | 로그인 항목 | 설정에서 켤 때 |

임시 서명으로 빌드되기 때문에, 다시 빌드하면 macOS가 손쉬운 사용 권한을 잊을 수 있습니다.

## 재생 정보를 읽는 방식

macOS 15.4부터 비공개 MediaRemote 프레임워크는 Apple이 서명한 프로세스에만 응답합니다. Nunsseop은 작은 헬퍼 라이브러리(`Sources/NowPlayingHelper`)를 시스템의 `/usr/bin/perl` 안에서 실행해 재생 정보를 읽고 재생·일시정지·다음·이전·위치 이동 명령을 보내며, 결과를 JSON으로 앱에 전달합니다.

비공개 API와 Apple 서명 바이너리에 대한 macOS의 동작에 기대는 방식이라, 이후 macOS 업데이트에서 막힐 수 있습니다. 헬퍼를 쓸 수 없으면 Music·Spotify는 AppleScript로, 브라우저는 음악·영상 사이트 탭을 읽는 방식으로 자동 전환됩니다. 이 대체 경로는 브라우저마다 *Apple Events의 자바스크립트 허용*을 켜야 합니다(Dia는 해당 메뉴가 없어 `--enable-applescript-javascript` 옵션으로 실행해야 합니다).

## 개인정보

Nunsseop은 개인 정보를 수집하거나 전송하지 않습니다. 네트워크는 다음에만 사용합니다.

- 하루에 한 번 `api.github.com`에서 새 릴리스가 있는지 확인 (설정에서 끌 수 있음)
- 이 Mac의 도구가 보내는 알림을 `127.0.0.1:47750`에서 받기 (설정에서 끌 수 있음)
- 재생 중인 곡의 가사를 `lrclib.net`에서 조회 (설정에서 끌 수 있음)
- 입력한 도시의 날씨를 `open-meteo.com`에서 조회 (도시를 입력하기 전에는 꺼져 있음)
- MediaRemote 헬퍼를 쓸 수 없을 때, 알려진 음악·영상 서비스의 이미지 서버에서 HTTPS로 앨범아트 다운로드

카메라 화면은 미러 탭이 열려 있을 때만 표시되며 녹화되지 않습니다. 클립보드 기록은 메모리에만 있고 앱을 끄면 지워집니다.

## 라이선스

[MIT](LICENSE)
