# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AmneziaWG userspace daemon + web UI addon for ASUS routers running Asuswrt-Merlin 388.x/3006.x firmware. Provides DPI-obfuscated WireGuard VPN with per-device policy routing and GeoIP/GeoSite selective routing.

**Targets:**
- **ARM64 (aarch64):** GT-AX11000, RT-AX86U, RT-AX88U Pro, etc. (HND platform, Kernel 4.1.51+)
- **ARMv7 (armhf):** RT-AX5400, RT-AX58U, etc. (Kernel 4.19+)

## Build

```bash
# Build amneziawg-go (userspace) via Docker
./build-go.sh                 # default: arm v7
./build-go.sh v0.2.18 arm64   # for 64-bit routers

# Build awg CLI tool
./build.sh                    # ARM64
DOCKER_BUILDKIT=1 docker build -f Dockerfile.arm32 --output=output . # ARMv7
```

## Architecture

### Userspace vs Kernel Module
While an AmneziaWG kernel module is available, this project defaults to **`amneziawg-go` (userspace)**.
- **Why:** The kernel module conflicts with the ASUS "Flow Control" (Hardware Acceleration) feature on many models, leading to system instability or bypass of VPN routing. The userspace daemon via TUN interface is more stable across diverse Merlin hardware.

### Memory Optimizations (Critical)

Low-RAM routers (512MB) require specific tuning for `amneziawg-go` stability:
- **Bounded Pools:** `amneziawg-go` is patched in `Dockerfile.go` to set `PreallocatedBuffersPerPool = 1024`. Default `0` leads to unbounded OOM during 4K streaming.
- **Queue Sizes:** Internal queues (Inbound/Outbound/Handshake) are maintained at **1024**. Reducing these to 256 or 512 results in protocol deadlocks and handshake loops during high-load scenarios.
- **Go Runtime:** `addon/amneziawg.sh` starts the daemon with `GOMEMLIMIT=320MiB` and `GOGC=20` to prevent heap exhaustion.
- **Resilient Watchdog:** The 5-minute watchdog uses 3 pings to verify connectivity, preventing full restarts on transient packet loss.
- **Async Processing:** Domain pre-resolution and firewall setup utilize background subshells and robust locking to prevent UI hangs.

### Build pipeline (`Dockerfile`)
Multi-stage Docker build: downloads Merlin toolchain + kernel source, applies router's kernel config, builds out-of-tree AmneziaWG kernel module and userspace tools from upstream repos. Uses `docker build --output` to export artifacts.

### Router-side components

**`addon/amneziawg.sh`** — Main backend script (runs on router). Handles:
- Interface lifecycle: `start`/`stop`/`restart` (insmod, ip link, awg setconf, iptables, ip rule)
- Config generation: Reads from `custom_settings.txt`. Obfuscation parameters `I1-I5` are stored individually (e.g., `awg_i1`) to bypass single-variable length limits in Merlin's storage.
- Per-device routing policy: `vpn_all`, `vpn_geo`, `direct` via ip rules + iptables mangle marks
- GeoIP/GeoSite: Dynamic GeoIP downloading based on `awg_geo_v2fly_ip`. Populates `ipset` (`awg_dst`) + `dnsmasq` ipset rules.
- Web UI addon mounting via Merlin Addons API (`am_get_webui_page`, menuTree.js bind mount)
- Service event dispatch (called from `/jffs/scripts/service-event`)

**`addon/amneziawg_page.asp`** — Web UI page (ROG-styled ASP). Communicates with backend via Merlin's `httpApi` custom settings and service events. Features a case-insensitive configuration importer and support for long hex-encoded obfuscation strings (max 2048 chars).

**`install.sh`** — One-shot installer (runs on router via SSH). Copies files, tests module loading, creates init script, installs addon page.

### Key paths on router
- `/opt/amneziawg/` — module, tool, config, client list, geo data
- `/jffs/addons/amneziawg/` — addon script + ASP page
- `/jffs/configs/dnsmasq.conf.add` — domain-based routing rules (tagged with `### AmneziaWG`)
- `/jffs/addons/custom_settings.txt` — Merlin settings store (all keys prefixed `awg_`)

### Routing model
Three policies per device: `vpn_all` (ip rule → table 200), `vpn_geo` (iptables fwmark 0x100 + ipset match → table 200), `direct`. 

**Best Practices for VPN Geo:**
- **GeoIP (IP-based):** Best for messaging apps (Telegram) or services with stable IP ranges (Cloudflare, Microsoft). Avoid overly broad ranges like "google" unless necessary.
- **GeoSite (Domain-based):** Preferred for massive CDNs (YouTube, TikTok, Netflix) or developer services (category-dev, github). Precise and memory-efficient.

## Shell scripting notes

All router-side scripts must be POSIX sh (busybox ash) — no bashisms. The router runs BusyBox with limited coreutils.
