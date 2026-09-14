<div align="center">

# VirusDownloader

**A high-performance, cross-platform desktop download manager built with Flutter.**

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-222222.svg?style=for-the-badge)](https://flutter.dev/multi-platform/desktop)
[![Architecture](https://img.shields.io/badge/Architecture-Clean%20%2F%20MVVM-blue.svg?style=for-the-badge)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)

</div>

---

## Overview

VirusDownloader is a modern desktop download manager engineered for speed, reliability, and direct browser integration. Built with Flutter and Dart, it combines a streamlined desktop interface with an asynchronous networking core tailored for high-bandwidth file transfers and dynamic media streams.

---

## Key Highlights

Beyond standard file downloading capabilities, VirusDownloader includes several specialized components:

* **Segmented Multi-Connection Engine**  
  Partitions files into dynamic byte-range segments downloaded across concurrent streams, significantly improving throughput on high-latency connections and stitching parts in real time.

* **Native HLS Stream Grabber and Remuxing**  
  Parses HTTP Live Streaming (`.m3u8`) playlists to download video segments in parallel, automatically assembling and remuxing them into complete media files via an integrated FFmpeg pipeline.

* **Local Bridge Browser Extension**  
  Operates an internal loopback server (`127.0.0.1:9849`) that interfaces directly with a companion Chromium extension (Chrome, Edge, Brave) to catch browser downloads automatically.

* **Proxy Routing and Hash Verification**  
  Supports configurable SOCKS5 and HTTP proxy configurations alongside pre- and post-transfer cryptographic checksum verification (MD5 and SHA-256).

---

## Build Requirements

| Component | Requirement | Details |
| :--- | :--- | :--- |
| Flutter SDK | >= 3.22.0 | Stable channel |
| Dart SDK | >= 3.4.0 < 4.0.0 | Included with Flutter SDK |
| Desktop Build Tools | Platform-specific | Visual Studio (Windows), Xcode (macOS), build-essential (Linux) |

---

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/f4rh4d-4hmed/VirusDownloader.git
cd VirusDownloader
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run the Application

```bash
# Windows
flutter run -d windows

# macOS
flutter run -d macos

# Linux
flutter run -d linux
```

### 4. Build for Release

```bash
# Windows executable
flutter build windows --release

# macOS application
flutter build macos --release

# Linux binary
flutter build linux --release
```

---

## Browser Extension Integration

VirusDownloader includes a Manifest V3 companion extension for Chromium-based browsers:

1. Open your browser and navigate to `chrome://extensions` or `edge://extensions`.
2. Enable **Developer mode** using the toggle switch.
3. Click **Load unpacked** and select the following folder within the project:
   ```text
   extras/extension
   ```
4. Keep VirusDownloader running in the background. Captured downloads will be routed directly to the desktop queue via the internal bridge.

*Note for Windows users: You can also execute `extras/install_extension.bat` to launch your browser with the extension automatically loaded.*

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for terms.
