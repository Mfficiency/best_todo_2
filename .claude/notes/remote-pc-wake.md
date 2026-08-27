# Remote PC wake + remote APK builds

> Goal: leave the Windows build machine powered off (or asleep) to save power,
> then wake it and kick off `tool/build.sh` / `tool/publish_apk.dart` from
> somewhere else — a phone, another computer, or a Claude Code session.

## Why this is a doc, not a feature

Waking a specific physical machine on a home network requires either being
*on that network* or having something that already lives there relay the
request. A cloud AI session (this one included) runs in an isolated
container with no route to your home LAN, so it cannot send the wake signal
itself — that part has to run from a device you control. This note is the
setup so *you* (or a relay device) can do it in a few seconds, and the
follow-up steps to actually run a build once the machine is up.

Two separate problems, solved separately:

1. **Wake the machine** — get it from off/asleep to running.
2. **Trigger the build** — once it's up, actually run
   `tool/build.sh apk --release` (or `PUBLISH_APK=1 sh tool/build.sh apk --release`).

## 1. Wake the machine

### 1a. Enable Wake-on-LAN on the laptop (one-time setup)

All three of these have to be true, or the magic packet is ignored:

- **BIOS/UEFI**: enable "Wake on LAN" / "Power On by PCI-E/PCIE" (varies by
  vendor — look under Power Management).
- **NIC driver** (Device Manager → Network adapters → your adapter →
  Properties → Power Management tab): check "Allow this device to wake the
  computer" and, on the Advanced tab, set "Wake on Magic Packet" to Enabled.
- **Windows power settings**: Control Panel → Power Options → "Choose what
  the power buttons do" → disable **Fast Startup**. Fast Startup hibernates
  instead of fully shutting down and breaks WOL-from-shutdown on many NICs.
  WOL from **Sleep (S3)** works without touching Fast Startup, so if you're
  okay leaving the machine sleeping instead of powered off, that's the more
  reliable option — sleep instead of shutdown.
- Note the laptop's MAC address (`ipconfig /all`) — Wi-Fi WOL is unreliable
  on most consumer hardware, so prefer a wired Ethernet connection if the
  laptop has one; Ethernet MAC is what you want here.

### 1b. Get the magic packet from outside the LAN to the laptop

WOL packets are a LAN broadcast — something on the same network segment has
to emit one. Pick one, roughly in order of effort:

- **Router-native WOL-over-WAN**: some routers (ASUS, Netgear, some
  OpenWrt/DD-WRT builds) have a built-in "Wake up a device" widget reachable
  from their remote-management app/DDNS. Check your router's admin page
  first — if it has this, you're done and can skip the rest of this section.
- **Recommended: a Tailscale relay.** Install [Tailscale](https://tailscale.com)
  (free tier) on the laptop *and* on one always-on device on the same LAN
  (a Raspberry Pi, a NAS, or even your phone when it's on the home Wi-Fi).
  Tailscale SSH into the relay device from anywhere, then run
  `tool/wake_on_lan.py <laptop MAC>` from it (or `wakeonlan <MAC>` if that's
  installed) — this reaches the laptop because the relay is on the same
  broadcast domain. This is the same pattern as the built-in "Wake other
  devices" feature some Tailscale subnet routers expose.
- **Fallback: TeamViewer's Wake-on-LAN.** If TeamViewer is already installed
  on the laptop and stays paired with another always-on device on the same
  network, TeamViewer can send the WOL packet for you from its app/website —
  no extra setup beyond having it installed once while the laptop is on.
- **Avoid**: forwarding UDP port 9 on your router straight to the internet.
  Most routers won't let you forward to a broadcast address anyway, and the
  ones that do turn your LAN into an easy target — don't do this. Route the
  request through a VPN (Tailscale) or your router's own authenticated WOL
  feature instead.

### 1c. Send the packet

```bash
python3 tool/wake_on_lan.py AA:BB:CC:DD:EE:FF          # broadcasts on 255.255.255.255:9
python3 tool/wake_on_lan.py AA:BB:CC:DD:EE:FF 192.168.1.255 9   # explicit subnet broadcast
```

No dependencies beyond Python 3's standard library, so it runs as-is on the
relay device (Pi, NAS, another laptop). Give it a minute or two — Windows
resume from Sleep is fast, resume from a full shutdown is slower.

## 2. Trigger the build once it's up

Pick based on how hands-on you want to be:

- **RDP** (simplest, interactive): enable Remote Desktop on the laptop
  (Settings → System → Remote Desktop, needs Windows Pro), reach it over the
  same Tailscale network (`<laptop tailscale name>:3389`, no port forwarding
  needed), and just open a terminal and run the build command yourself —
  including starting a Claude Code session there if you want AI-driven builds.
- **Headless, recommended for scripting**: enable **OpenSSH Server** on
  Windows (Settings → Apps → Optional Features → Add "OpenSSH Server"), then
  `ssh` in over Tailscale and run:
  ```powershell
  cd C:\path\to\best_todo_2
  git pull
  sh tool/build.sh apk --release        # or: PUBLISH_APK=1 sh tool/build.sh apk --release
  ```
  (run from Git Bash / WSL, or use `tool/build.ps1` from PowerShell directly).
- **Fully automated**: register the laptop as a
  [self-hosted GitHub Actions runner](https://docs.github.com/actions/hosting-your-own-runners)
  for this repo, add a `workflow_dispatch`-triggered job that runs the build
  on it, then all you need after waking the machine is to trigger the
  workflow from the GitHub app/website or `gh workflow run`. This is more
  setup up front but means "wake + build" becomes a single button press from
  anywhere, with no manual SSH step. Not implemented yet — worth doing if
  the manual SSH step above becomes a chore.

## End-to-end recipe (recommended)

1. One-time: enable WOL in BIOS + NIC driver (§1a), disable Fast Startup,
   install Tailscale on the laptop, install Tailscale + this repo's
   `tool/wake_on_lan.py` on one always-on relay device on the same LAN,
   enable OpenSSH Server on the laptop.
2. Each time you need a build: SSH into the relay over Tailscale → run
   `tool/wake_on_lan.py <laptop MAC>` → wait ~30-60s → SSH into the laptop
   over Tailscale → `sh tool/build.sh apk --release`.

## Remember

- CI already builds an APK on every push via `.github/workflows` — waking
  the laptop is only needed when you specifically want a *local* build (e.g.
  to test the Windows integration/screenshot suite, or to sign/publish from
  the machine with your local `GITHUB_TOKEN`/`gh` login).
- The laptop needs to be reachable (network-wise) for the SSH/RDP step too —
  Tailscale covers both the wake-relay hop and this hop with one install.
