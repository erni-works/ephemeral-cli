# ephemeral CLI

[Ephemeral AI](https://ephemer.al) runs disposable AI agents. One API call supplies instructions, input, files and authenticated HTTP/MCP connections, or names a saved workflow; Ephemeral starts the agent in a fresh, isolated worker, streams its events, records the result and destroys the worker. `ephemeral` is the command-line client for that API: start and watch runs, manage workflows, schedules, files and connections, and call any other endpoint.

This repository publishes signed `ephemeral` binaries for macOS, Linux and Windows. The source code is not public.

## Install

macOS and Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/erni-works/ephemeral-cli/main/install.sh | sh
```

Windows (PowerShell 5.1 or later):

```powershell
irm https://raw.githubusercontent.com/erni-works/ephemeral-cli/main/install.ps1 | iex
```

`https://ephemer.al/install.sh` and `https://ephemer.al/install.ps1` redirect to the same scripts.

The installer downloads the latest release for your system, checks it against the release's `checksums.txt`, and installs it without administrator rights:

| System | Location | Notes |
| --- | --- | --- |
| macOS, Linux | `~/.local/bin/ephemeral` | Prints the line to add if the directory is not on your `PATH`. |
| Windows | `%LOCALAPPDATA%\Programs\ephemeral\bin\ephemeral.exe` | Adds the directory to your user `PATH`; open a new terminal afterwards. |

Installer settings, all optional:

| Variable | Effect |
| --- | --- |
| `EPHEMERAL_VERSION` | Install this release, e.g. `v1.2.3`, instead of the latest. |
| `EPHEMERAL_INSTALL_DIR` | Install into this directory instead. |
| `EPHEMERAL_DOWNLOAD_BASE` | Download from another copy of this repository's releases. |

```sh
curl -fsSL https://raw.githubusercontent.com/erni-works/ephemeral-cli/main/install.sh | EPHEMERAL_VERSION=v1.2.3 EPHEMERAL_INSTALL_DIR="$HOME/bin" sh
```

Builds are provided for macOS (Intel and Apple silicon), Linux (x86-64 and ARM64; static, so any distribution) and Windows (x64 and ARM64).

## Sign in

Create an API key under **Keys** in the [dashboard](https://app.ephemer.al), then:

```sh
ephemeral login     # paste the key; it is not shown
ephemeral status    # shows the organization and role of the key
```

`login` checks the key with the API before saving it, together with the API URL, in your user configuration directory (`~/.config/ephemeral/config.json` on Linux, `~/Library/Application Support/ephemeral/config.json` on macOS, `%APPDATA%\ephemeral\config.json` on Windows), readable only by you. In scripts, pipe the key instead: `printf '%s\n' "$KEY" | ephemeral login`. `ephemeral logout` removes it.

| Variable | Effect |
| --- | --- |
| `EPHEMERAL_API_KEY` | API key; takes precedence over the saved key. |
| `EPHEMERAL_URL` | API URL, for a self-hosted installation; default `https://app.ephemer.al` or the URL saved by `login --url`. A saved key is sent only to the URL it was saved for. |
| `EPHEMERAL_NO_UPDATE_CHECK=1` | Turn off the daily check for a newer version. |

Then, for example:

```sh
ephemeral run --prompt 'Summarize the attached notes.' --file ./notes.md --wait
ephemeral help
```

The full API is described in the [Ephemeral documentation](https://ephemer.al/docs).

## Update

```sh
ephemeral update                     # install the latest release
ephemeral update --check             # only report whether one is available
ephemeral update --version v1.2.3    # install a specific release, including pre-releases
```

`ephemeral update` replaces the running executable in place after checking the release's signature and checksum; nothing is installed if either check fails. If the executable's directory is not writable, re-run the command with `sudo` or reinstall with the installer. Once a day, interactive commands also check in the background whether a newer version exists and print a one-line notice; the check never delays or fails a command, and is skipped in CI (`CI` set) and with `EPHEMERAL_NO_UPDATE_CHECK=1`.

## Verify a download

Each release contains `checksums.txt` (SHA-256 of every archive) and `checksums.txt.sig`, a base64 Ed25519 signature of `checksums.txt` made with the key in [`ephemeral-release.pub.pem`](ephemeral-release.pub.pem). `ephemeral update` performs both checks itself. To check a download by hand (OpenSSL 3 is required; on macOS, the system `openssl` is LibreSSL, so use `brew install openssl@3`):

```sh
VERSION=1.2.3
ARCHIVE=ephemeral_${VERSION}_linux_amd64.tar.gz   # or _darwin_arm64.tar.gz, _windows_amd64.zip, ...
BASE=https://github.com/erni-works/ephemeral-cli/releases/download/v$VERSION
curl -fsSLO "$BASE/$ARCHIVE" -O "$BASE/checksums.txt" -O "$BASE/checksums.txt.sig"
curl -fsSLO https://raw.githubusercontent.com/erni-works/ephemeral-cli/main/ephemeral-release.pub.pem

# 1. checksums.txt was signed by Ephemeral ("Signature Verified Successfully").
openssl base64 -d -A -in checksums.txt.sig -out checksums.txt.sig.bin
openssl pkeyutl -verify -pubin -inkey ephemeral-release.pub.pem -rawin -in checksums.txt -sigfile checksums.txt.sig.bin

# 2. The archive matches checksums.txt (macOS: shasum -a 256 --ignore-missing -c checksums.txt).
sha256sum --ignore-missing -c checksums.txt

# 3. Install the executable from the archive.
tar -xzf "$ARCHIVE" ephemeral && mkdir -p ~/.local/bin && install -m 755 ephemeral ~/.local/bin/ephemeral
```

On Windows, compare `(Get-FileHash ephemeral_1.2.3_windows_amd64.zip).Hash` with the line in `checksums.txt`, and check the signature with the same `openssl` commands using OpenSSL 3 (for example the one included with Git for Windows). The archive contains `ephemeral.exe`.

## Uninstall

macOS and Linux (use your `EPHEMERAL_INSTALL_DIR` if you set one):

```sh
rm -f ~/.local/bin/ephemeral
rm -rf ~/.config/ephemeral ~/.cache/ephemeral                                   # Linux
rm -rf ~/Library/Application\ Support/ephemeral ~/Library/Caches/ephemeral      # macOS
```

Windows:

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\ephemeral", "$env:APPDATA\ephemeral", "$env:LOCALAPPDATA\ephemeral" -ErrorAction SilentlyContinue
```

Then remove `%LOCALAPPDATA%\Programs\ephemeral\bin` from **Path** under *Edit environment variables for your account*.

## Releases

Each `releases/vX.Y.Z.json` manifest lists a release's archives with their sizes and SHA-256 digests. When a manifest is added, [the publish workflow](.github/workflows/publish.yml) fetches the signed files, verifies the signature against `ephemeral-release.pub.pem` and every checksum against the manifest, and only then creates the GitHub Release. Pre-releases (`v1.2.0-rc.1`) are never marked as latest, so the installers and `ephemeral update` install them only when asked for explicitly.

## License

The `ephemeral` CLI is proprietary and its source code is not public. The binaries are provided for use with Ephemeral AI under the Ephemeral AI terms of service.
