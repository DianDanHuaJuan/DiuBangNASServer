# Contributing

Thank you for your interest in contributing to **DiuBangFileS** (NASServer).

## Getting started

1. Fork the repository and clone your fork.
2. Install Flutter (Dart ^3.10.7 per `pubspec.yaml`) on **Windows 10/11 x64** for desktop builds.
3. Run `flutter pub get`.
4. Create a local `Encryption_key` at the project root before running or building the app:

   ```powershell
   Copy-Item Encryption_key.example Encryption_key
   ```

   `Encryption_key.example` documents the format and matches the public compatibility key used by [DiuBangNASClient](https://github.com/DianDanHuaJuan/DiuBangNASClient). Self-hosted deployments should generate their own independent random 32-character hexadecimal key, not derive one from the example, and use the same value on both client and server.

   For a local override you may place `Encryption_key` at the repository root (gitignored); the loader prefers that file at runtime.

5. Run the app: `flutter run -d windows`
6. Run tests: `flutter test`
7. Run the analyzer: `flutter analyze`

## Pull requests

- Keep changes focused; one logical change per PR when possible.
- Add or update tests for behavior changes.
- Ensure `flutter analyze` and `flutter test` pass locally before opening a PR.
- Do not include secrets, debug log dumps, or personal network identifiers in commits.

## Code style

- Follow existing patterns under `lib/core` and `lib/features`.
- Use the established feature layout: `data/`, `domain/`, `application/`, `presentation/` where applicable.
- Prefer meaningful names over comments that restate the code.

## Security

See [SECURITY.md](SECURITY.md) before reporting or fixing security-sensitive areas (owner credentials, TLS, encryption key handling, Relay data scope).

## Questions

Open a GitHub issue for bugs or feature discussions. For security issues, follow SECURITY.md instead of filing a public issue with exploit details.
