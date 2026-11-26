# Moss

**Smaller files, right on your computer.** Moss makes any video, sound or photo fit where it's going: smaller, trimmed, sound only, converted, or ready for Discord, WhatsApp or email. Everything happens on your own computer. Nothing is uploaded.

This page is where Moss is downloaded. Moss's own code is private; this repository only holds the releases and the notes below.

## Download

| | Download | Needs |
|---|---|---|
| **Moss for Mac** | [Latest Mac release](https://github.com/TheFlamesOfFury/moss-releases/releases/tag/mac-v1.0.0) (`Moss-1.0.0.dmg`) | macOS 26 or later, Apple-chip or Intel |
| **Moss for Windows** | [Latest Windows release](https://github.com/TheFlamesOfFury/moss-releases/releases/tag/windows-v0.3.2) (`Moss-Setup-0.3.2.exe`) | 64-bit Windows 10 (version 2004 or later) or Windows 11 |

Each release lists the file's SHA-256, so you can check your download.

### Installing on a Mac
Open the DMG and drag Moss to Applications. Moss isn't notarised yet, so the first time macOS stops it: go to **System Settings → Privacy & Security** and click **Open Anyway** (once).

### Installing on Windows
Run `Moss-Setup-0.3.2.exe`. It installs for your Windows user only (no admin needed) and includes everything Moss needs. Moss isn't code-signed yet, so Windows may say "Windows protected your PC" or "unknown publisher": choose **More info → Run anyway**. Uninstall from **Settings → Apps**.

Moss for Windows can check for updates once a day. It's off until you switch it on (on the welcome page or in Settings). Updates are signed, and Moss checks the signature and the file before installing anything.

## Privacy, in short
- Your files stay on your computer. Moss works on them there and saves the results next to the originals (or in a folder you choose).
- No accounts, ads, analytics or tracking. Moss doesn't collect any data.
- "Type what you need" is understood on your computer. Nothing you type is sent anywhere.
- The only thing Moss ever asks the internet for is the optional Windows update check, and that request carries only "Moss" and its version number.

## Open-source software in Moss
Moss includes a separate helper program, **FFmpeg**, for some file formats, built from source with **LAME**, **libwebp**, and on Windows also **Opus**, **libaom** and **zlib**. FFmpeg is used under the GNU LGPL; the others under their own permissive licences. Each licence is shipped with Moss and shown in **Settings → Open-source software**.

The exact recipes used to build that helper are in [`source/`](source):
- Mac: [`source/scripts/build-ffmpeg.sh`](source/scripts/build-ffmpeg.sh) with the pinned source hashes in [`source/scripts/ffmpeg-hashes.env`](source/scripts/ffmpeg-hashes.env)
- Windows (MSYS2 MINGW64): [`source/Apps/Windows/build-ffmpeg.sh`](source/Apps/Windows/build-ffmpeg.sh)

They download the unmodified official source releases (checked by SHA-256) and build them without changes. You can rebuild the helper with them and swap it into Moss: on a Mac it's `Moss.app/Contents/Helpers/ffmpeg`, on Windows `Helpers\ffmpeg.exe` in Moss's install folder.
