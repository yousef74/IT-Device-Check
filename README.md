# IT Device Check

[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=flat&logo=windows)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=flat&logo=powershell)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **A single PowerShell script that generates a modern, interactive HTML dashboard for IT Help Desk and Technical Support — hardware, OS, security, Kaspersky, and battery health in one click.**

---

## Features

| Page | What it shows |
|------|---------------|
| **Device** | System info, Windows edition/build/license, CPU, RAM, GPU, storage (with usage bars), network adapters (MAC on one line), domain, Microsoft Office, TPM, Secure Boot, Defender |
| **Kaspersky** | Endpoint Security version + service status, Network Agent version + status, KSC server connection + last sync, license status |
| **Battery** | Animated health gauge, design vs full charge capacity, EXCELLENT / GOOD / FAIR / WEAK rating |

- **No dependencies** — just PowerShell 5.1 (built into Windows 10/11)
- **Auto-opens in browser** — no console to read
- **Color-coded** — green = healthy, red = problem, orange = warning
- **Saves HTML** to Desktop for sharing or archiving

---

## Usage

### Quick Start (recommended)

1. Download or clone this repo
2. Right-click `DeviceDashboard.ps1` → **Run with PowerShell**
3. If prompted, click **Yes** for Administrator access
4. Wait ~10 seconds — the dashboard opens in your browser

### Via Command Line

```powershell
# Open PowerShell in the folder, then run:
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
& "C:\path\to\DeviceDashboard.ps1"
```

### Double-Click Launcher

Double-click `Run Dashboard.bat` — it bypasses execution policy and runs the script automatically.

---

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 (included by default)
- Administrator privileges (recommended for full results)

---

## How It Works

The script uses Windows built-in tools to gather everything in one run:

- **CIM/WMI** — hardware, OS, CPU, RAM, GPU, storage, network
- **Registry** — Windows license, Kaspersky license
- ** powercfg** — battery report
- **Kaspersky tools** — `avp.com`, `klnagchk.exe` for KES/KSC status

All data is rendered into a single self-contained HTML file with embedded CSS and JavaScript — no external libraries, no internet required.

---

## Screenshots

### Device Page
![Device Page](https://img.shields.io/badge/Device-Hardware%20%7C%20OS%20%7C%20Network%20%7C%20Security-blue)

### Kaspersky Page
![Kaspersky Page](https://img.shields.io/badge/Kaspersky-KES%20%7C%20Agent%20%7C%20KSC%20%7C%20License-red)

### Battery Page
![Battery Page](https://img.shields.io/badge/Battery-Health%20Gauge%20%7C%20Capacity%20%7C%20Status-green)

---

## Project Structure

```
IT-Device-Check/
├── DeviceDashboard.ps1    # The main script (self-contained)
├── Run Dashboard.bat      # Double-click launcher
├── README.md              # This file
├── LICENSE                # MIT License
└── .gitignore             # Ignores generated files
```

---

## License

[MIT](LICENSE) — free to use, modify, and distribute.

---

## Contributing

Found a bug or want to add a feature? Open an issue or submit a pull request.

---

<div align="center">

**Built for IT Help Desk & Technical Support**

</div>
