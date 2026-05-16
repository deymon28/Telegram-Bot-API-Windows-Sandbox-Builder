# Telegram Bot API — Windows Sandbox Builder

Build a fully **static, standalone** `telegram-bot-api.exe` (the [tdlib Local Bot API Server](https://github.com/tdlib/telegram-bot-api)) inside a **disposable Windows Sandbox**, so your host machine stays clean. A pre-built binary is also included for convenience.

---

## What is this?

The [Telegram Local Bot API](https://core.telegram.org/bots/api#using-a-local-bot-api-server) lets you run a self-hosted Telegram Bot API server. This removes the 50 MB file upload limit, gives you access to local file paths, and eliminates rate limits on sending files.

Building it on Windows from source requires Git, CMake, Visual Studio Build Tools, vcpkg, and several C++ dependencies — a messy setup to do on a real machine. This project automates everything inside a **Windows Sandbox**, a disposable lightweight VM that disappears when you close it. The result is a single portable `.exe` you drag out before closing.

---

## Repository Contents

| File | Description |
|---|---|
| `build-telegram-bot-api.ps1` | Original build script (hardcoded tool versions) |
| `build-telegram-bot-api_-_actual.ps1` | **Recommended.** Same script but fetches the latest Git and CMake versions automatically via GitHub API |
| `sandbox.wsb` | Windows Sandbox configuration (8 GB RAM) |
| `telegram-bot-api.exe` | Pre-built binary — skip the build entirely if you just need the `.exe` |

---

## Requirements

### 1. Enable Virtualization in BIOS/UEFI

Windows Sandbox requires hardware virtualization. If it is not enabled, the Sandbox will fail to start.

**How to check if it is already enabled:**

Open Task Manager → Performance tab → CPU. Look for **Virtualization: Enabled** in the bottom-right section.

Alternatively, open PowerShell and run:
```powershell
(Get-WmiObject Win32_Processor).VirtualizationFirmwareEnabled
```
If the result is `True`, you are good. If `False`, you need to enable it in BIOS.

**How to enable it:**

1. Restart your PC and enter BIOS/UEFI setup. The key varies by manufacturer — commonly `Del`, `F2`, `F10`, or `F12` during POST.
2. Find the virtualization setting. It is usually under **Advanced**, **CPU Configuration**, or **Security**:
   - Intel CPUs: look for **Intel Virtualization Technology (VT-x)**
   - AMD CPUs: look for **AMD-V** or **SVM Mode**
3. Set it to **Enabled**.
4. Save and exit (usually `F10`).

### 2. Enable Windows Sandbox Feature

Windows Sandbox is available on **Windows 10/11 Pro, Enterprise, and Education** (not Home).

**Option A — via Windows Features GUI:**

1. Press `Win + R`, type `optionalfeatures`, press Enter.
2. Scroll down to **Windows Sandbox**, check the box, click OK.
3. Restart when prompted.

**Option B — via PowerShell (run as Administrator):**

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All
```

Restart when prompted.

**Verify it works:**

Press `Win`, search for **Windows Sandbox** — if it appears and opens a window, you are ready.

---

## Quick Start — Use the Pre-Built Binary

If you just need `telegram-bot-api.exe` and do not want to build from source, you can use the binary included in this repository directly.

See **[Running the Server](#running-the-server)** below.

---

## Build from Source (inside Windows Sandbox)

> **Expected total time: 2–3 hours.** Most of it is unattended — you can walk away after starting.

### Step 1 — Copy the build script to your host machine

Save `build-telegram-bot-api_-_actual.ps1` to `C:\` on your **host** machine:

```
C:\build-telegram-bot-api.ps1
```

> The script must be at `C:\build-telegram-bot-api.ps1` exactly, or adjust the path in `sandbox.wsb` (see note below).

### Step 2 — Edit `sandbox.wsb` to expose the script (important)

The included `sandbox.wsb` does not automatically share your host folders with the Sandbox. You need to add a `MappedFolders` section so the script is accessible inside the Sandbox.

Open `sandbox.wsb` in any text editor and replace its contents with:

```xml
<Configuration>
  <MemoryInMB>8192</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>C:\</HostFolder>
      <SandboxFolder>C:\HostShare</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell -ExecutionPolicy Bypass -File C:\HostShare\build-telegram-bot-api.ps1</Command>
  </LogonCommand>
</Configuration>
```

This maps your host `C:\` as a read-only folder inside the Sandbox at `C:\HostShare` and auto-launches the script on startup.

Alternatively, you can skip editing and manually copy-paste the script inside the Sandbox after it opens.

### Step 3 — Launch the Sandbox

Double-click `sandbox.wsb`. A Windows Sandbox window will open. If you added `LogonCommand`, the build starts automatically. Otherwise, open PowerShell inside the Sandbox and run:

##### Run `PowerShell` as administrator

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
powershell -ExecutionPolicy Bypass -File C:\build-telegram-bot-api.ps1
```
##### OR if you use actual.ps1(and if path in PowerShell - `C:\Windows\system32>`) use:

```powershell
cd ..\..
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
powershell -ExecutionPolicy Bypass -File "C:\build-telegram-bot-api - actual.ps1"
```

### Step 4 — Wait for the build to finish

The script runs 12 steps automatically:

1. Downloads and installs the latest Git
2. Downloads and installs the latest CMake
3. Downloads and installs Visual Studio Build Tools 2022 (C++ workload)
4. Configures MSVC compiler PATH
5. Creates build directories
6. Clones `tdlib/telegram-bot-api` with submodules
7. Clones `Microsoft/vcpkg`
8. Bootstraps vcpkg
9. Creates a static linkage triplet (`x64-windows-static`)
10. Installs dependencies via vcpkg: `gperf`, `openssl`, `zlib` — **this is the longest step (30–60 min)**
11. Configures CMake and compiles — **(40–60 min)**
12. Copies the result to `C:\Export\telegram-bot-api.exe`

### Step 5 — Export the binary

When the build completes, the file is at `C:\Export\telegram-bot-api.exe` **inside the Sandbox**.

Drag and drop it from the Sandbox window to a folder on your host machine before closing. Once the Sandbox window is closed, all Sandbox data is permanently deleted.

---

## Running the Server

You need a Telegram `api_id` and `api_hash`. Get them at [my.telegram.org](https://my.telegram.org/apps).

**Minimal launch (local mode):**

```cmd
telegram-bot-api.exe --api-id=YOUR_API_ID --api-hash=YOUR_API_HASH --local
```

**With custom port and log file:**

```cmd
telegram-bot-api.exe --api-id=YOUR_API_ID --api-hash=YOUR_API_HASH --local --http-port=8081 --log=C:\logs\bot-api.log
```

**Common flags:**

| Flag | Description |
|---|---|
| `--local` | Enable local mode (required for full functionality) |
| `--http-port=N` | Port to listen on (default: `8081`) |
| `--dir=PATH` | Directory to store downloaded files |
| `--log=PATH` | Path to log file |
| `--verbosity=N` | Log verbosity level (0–10, default: 5) |
| `--max-webhook-connections=N` | Max simultaneous webhook connections |

Once running, use your bot with the local server by pointing the Bot API base URL to `http://127.0.0.1:8081/bot` instead of `https://api.telegram.org/bot`.

**Example with `python-telegram-bot`:**

```python
from telegram.ext import ApplicationBuilder

app = (
    ApplicationBuilder()
    .token("YOUR_BOT_TOKEN")
    .base_url("http://127.0.0.1:8081/bot")
    .base_file_url("http://127.0.0.1:8081/file/bot")
    .local_mode(True)
    .build()
)
```

---

## Troubleshooting

**Sandbox won't start — "Virtualization not supported"**
→ Enable VT-x / AMD-V in BIOS (see Requirements above).

**Sandbox won't start — "Windows Sandbox is not installed"**
→ Enable the Windows feature (see Requirements above). Make sure your Windows edition is Pro or Enterprise.

**Build fails at vcpkg install with a network error**
→ Check your firewall or antivirus. The Sandbox needs internet access. Try temporarily disabling real-time protection.

**`cl.exe` or compiler not found**
→ VS Build Tools installation may have failed silently. Re-run the script — it is idempotent.

**EXE not found at `C:\Export` after build**
→ Check if `C:\Build\telegram-bot-api\bin\telegram-bot-api.exe` exists inside the Sandbox. If it does, copy it manually to the host before closing.

---

## Notes

- The build produces a **fully statically linked** binary with no external DLL dependencies — just copy `telegram-bot-api.exe` anywhere and run it.
- The `_actual` script version dynamically resolves the latest Git and CMake releases at build time, so the script does not become outdated.
- Building with `/m:1` (single thread) is intentional — parallel compilation inside Sandbox can fail due to limited virtual CPU resources.
- The Sandbox has no persistent state. Every run starts from a clean Windows installation. This is by design.

---

## Credits

Builds [tdlib/telegram-bot-api](https://github.com/tdlib/telegram-bot-api) — the official Telegram Local Bot API Server by Telegram.
