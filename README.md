<p align="center"><img src="icon.png" alt="DefaultBrowser icon" width="128"></p>

<h1 align="center">DefaultBrowser (iOS 12)</h1>

**Open web links in the browser you choose instead of Safari.**

On iOS 12 every web link opens in Safari, even if you prefer another browser. DefaultBrowser fixes that: links that other apps open (Mail, Messages, Notes and so on) go to the browser you pick in Settings instead.

Safari still opens normally from its own icon, and "Open in Safari" inside another browser still works. If the browser you picked is removed, links simply go back to Safari.

This is an unofficial jailbreak tweak. It is not affiliated with or endorsed by Apple.

## Screenshots

Settings > Default Browser:

<img src="screenshots/settings.png" alt="Default Browser settings page" width="420">

## Features

- Works with Firefox, Chrome, Brave, DuckDuckGo, Firefox Focus, Firefox Klar, Microsoft Edge and Opera.
- The browser list only shows browsers that are installed.
- Falls back to Safari when the chosen browser is missing.
- Only plain web links (http and https) aimed at Safari are redirected. Links that already open in their own app (universal links such as YouTube or Maps) are not touched.
- On/off switch in Settings. Changes apply right away, no respring needed.
- Replaces the older FirefoxDefault tweak.

## Compatibility

- Tested on an iPad mini 2 with iOS 12.5.8, jailbroken with checkra1n + odysseyra1n (libhooker).
- Expected to work on iOS 12.x. It should work on iPhone too, but it has only been tested on iPad.
- The browser must be installed and support iOS 12. Microsoft Edge and Opera use link formats that are not officially documented; they are offered only when the installed app supports them.

## Install

Add the **iOS Legacy** source to your package manager, then search for DefaultBrowser:

```
https://itsallexb.github.io/ios-legacy/
```

One tap on your device: [Add to Sileo](https://itsallexb.github.io/ios-legacy/add/sileo.html) · [Add to Zebra](https://itsallexb.github.io/ios-legacy/add/zebra.html) · [Add to Cydia](https://itsallexb.github.io/ios-legacy/add/cydia.html)

Or download the `.deb` from [Releases](https://github.com/itsAllexB/DefaultBrowser-iOS12/releases/latest) and install it with Filza or `dpkg -i`, then respring.

Requires `mobilesubstrate` (Substrate, Substitute or libhooker) and PreferenceLoader. Your package manager installs them automatically.

## Settings

Open **Settings > Default Browser**:

- **Enabled**: turns the tweak on or off.
- **Browser**: the browser that web links open in. Only installed browsers are listed. The note under the list names the other supported browsers, which appear once you install them.

## Build from source

You need [Theos](https://theos.dev/docs/installation) and an iOS SDK (the Makefile uses the iOS 14.5 SDK and targets iOS 12.0, arm64).

```sh
git clone https://github.com/itsAllexB/DefaultBrowser-iOS12.git
cd DefaultBrowser-iOS12
make package FINALPACKAGE=1
```

The package is written to `packages/`. To install it on a device over SSH, set `THEOS_DEVICE_IP` and run `make install`.

How it works: when an app opens a web link, iOS asks SpringBoard to open Safari with that URL (`-[SBMainWorkspace systemService:handleOpenApplicationRequest:withCompletion:]`). The tweak rewrites requests aimed at Safari into the chosen browser's own URL scheme, for example `firefox://open-url?url=...` or `googlechromes://...`. The supported browsers and their URL formats are listed in [`DBBrowsers.h`](DBBrowsers.h).

## Credits and license

Made by [itsAllexB](https://github.com/itsAllexB).

DefaultBrowser is free software under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).

Safari is a trademark of Apple Inc.; other browser names are trademarks of their owners. This project is not affiliated with Apple or with any browser vendor.
