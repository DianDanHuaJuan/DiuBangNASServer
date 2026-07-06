# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-07-06

### Changed

- Replaced gyan.dev GPLv3 FFmpeg essentials with BtbN win64-lgpl static build
- HLS encoding now uses h264_mf / libopenh264 via FfmpegHlsEncoder (no libx264)
- Added unified Windows bootstrap tooling (tool/bootstrap_windows.ps1)
- build_installer.ps1 auto-bootstraps media_kit + FFmpeg and bundles THIRD_PARTY_NOTICES.txt
- Updated README, SECURITY, CONTRIBUTING, and packaging docs for LGPL compliance
- LICENSE copyright holder updated to DianDanHuaJuan

## [1.0.1] - 2026-07-06

### Changed

- Moved `Encryption_key.example` to project root for consistency with DiuBangNASClient
- Removed build artifacts, installer binaries, and IDE config from the public tree

## [1.0.0] - 2026-07-06

### Added

- MIT license and open-source README, SECURITY policy, and `Encryption_key.example` compatibility template
- CONTRIBUTING guide and GitHub CI workflow
- Windows desktop NAS server: WebDAV, control-plane API, Relay, preview/thumbnails within a user-selected shared folder

### Changed

- Initial public release baseline at version 1.0.0
- Removed internal-only documentation, design mockups, and development artifacts from the public tree

## [0.x] - (internal)

- Pre-open-source development history on private remotes
