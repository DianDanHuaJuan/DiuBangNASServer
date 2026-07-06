# Security Policy

## Reporting a Vulnerability

If you discover a security issue, please **do not** open a public GitHub issue with exploit details.

Report privately via GitHub Security Advisories for this repository, or contact the maintainer through the repository owner's profile.

We will acknowledge reports within a reasonable timeframe and coordinate a fix before public disclosure when appropriate.

## Supported Versions

Security fixes are applied to the default branch. There is no long-term support policy for older releases yet.

## Known Security Considerations

Review these before deploying in production or on untrusted networks.

### Default owner credentials

On first launch the server seeds a default owner account **`admin` / `admin`**. Remote clients cannot establish sessions until the owner changes these credentials in the local management UI. Treat any deployment that still uses the default password as compromised.

### Static `Encryption_key`

The server loads a symmetric key from `Encryption_key` at the project root (bundled at build time). The repository ships `Encryption_key.example` as a public compatibility template; it does not commit a production secret.

- Treat the example key, and any release built from it, as public compatibility data rather than a secret boundary.
- Self-hosted deployments should generate their own independent random `Encryption_key` before building, avoid deriving it from the example, and keep client/server values in sync.
- Anyone operating a deployment with a custom key is responsible for distributing and rotating that key safely.

### TLS (self-signed CA)

The server generates a private root CA and leaf certificate on first HTTPS startup. Clients must pair and pin the CA before trusting connections. Pairing must occur on a trusted LAN; do not expose the HTTP pairing endpoint to the public Internet without additional hardening.

### Shared directory scope

WebDAV and preview APIs operate on the user-selected shared folder only. A compromised device token or bearer session can read, write, and delete files within that folder. Limit shared-folder contents and revoke untrusted devices promptly.

### Relay

Relay transfers store metadata and payloads under the server's data directory. Compromised owner or device credentials may access in-flight or completed relay payloads. Use Relay only among trusted devices on a trusted network.

### Debug logging

Network debug logging may include request URLs and response bodies in debug builds. Do not enable verbose logging when handling sensitive data on shared machines.

### Android platform (legacy)

The `android/` tree is retained for historical compatibility but is **not** the primary supported platform for this open-source release. Release builds may fall back to debug signing when local keystore configuration is absent. Do not distribute unsigned or debug-signed Android builds.

### libmpv (installer bundle)

Windows builds bundle `libmpv-2.dll` via [media-kit/libmpv-win32-video-build](https://github.com/media-kit/libmpv-win32-video-build) (built with `-Dgpl=false`).

- Used in-process for local video preview through media_kit; not used for server-side HLS transcoding.
- Redistribution requires LGPL compliance. See [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

### FFmpeg (installer bundle)

Windows installer packaging bundles `ffmpeg.exe` from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) (`win64-lgpl` static build, 8.1 release branch). The file is placed under `assets/` during bootstrap (not committed to Git).

- FFmpeg is invoked as a **separate subprocess** for HLS transcoding and video thumbnails; it is not linked into the MIT-licensed application source.
- The bundled build excludes GPL-only components (e.g. libx264). H.264 encoding uses `h264_mf` or `libopenh264`.
- Redistribution requires LGPL compliance (notices, source offer). See [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).
