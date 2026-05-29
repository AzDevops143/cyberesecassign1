# Hexa Force: Advanced Container Security & Containment Lab

**Institution:** School of Artificial Intelligence and Data Science, IIT Jodhpur
**Authors:** Hexa Force Core Engineering Team (G25ait2026)

## Overview
Hexa Force is an educational integration study and instrumented containment framework for shared-kernel container environments. It models a complete four-stage container breakout exploit chain and demonstrates the efficacy of multi-layered defense mechanisms, including surgical system call filtering (Seccomp) and capability dropping.

This repository accompanies the IEEE format research paper: *"Securing Shared-Kernel Runtimes Against Kernel-Level Container Escapes."*

## The 4-Stage Threat Model
The lab simulates a cascading privilege escalation chain:
1. **Host Kernel Isolation (CVE-2016-5195):** Exploiting a Copy-on-Write (COW) race condition from within an unprivileged container process to overwrite a read-only root file.
2. **Namespace & Capabilities Isolation:** Abusing `CAP_SYS_PTRACE` and shared PID namespaces to inject code into host processes.
3. **Daemon & API Security:** Hijacking a mounted `/var/run/docker.sock` to gain raw engine control.
4. **Volume & Filesystem Security:** Exploiting writable host filesystem mounts to inject malicious tasks into the host's cron daemon for persistent access.

## Core Components

### 1. The Hexa Force COW Analysis Tool (`hexaforce_cow.c`)
An independently engineered, multi-mode analysis framework for the CVE-2016-5195 race condition. Unlike simple exploit scripts, this tool provides:
* **--probe:** Non-destructive vulnerability fingerprinting
* **--exploit:** Controlled race trigger with nanosecond-resolution timing telemetry
* **--verify:** Post-exploitation forensic integrity checking
* **--benchmark:** Statistical race window analysis (success rates, timings)

*(Attribution: The fundamental race condition technique—madvise + /proc/self/mem—was first publicly documented by Phil Oester in 2016 at dirtycow.ninja)*

### 2. Multi-Layer Seccomp Profile (`hexaforce-seccomp.json`)
An original, surgical 8-layer Seccomp BPF profile that neutralizes the Dirty COW race vector by blocking `madvise` and prevents namespace/filesystem escapes by restricting `ptrace`, `unshare`, and `mount`.

### 3. Benchmark Suite (`benchmark.sh`)
A utility script that measures the actual performance overhead of the deployed security controls, producing CSV-formatted empirical data on container startup latency, exploit containment rates, and Trivy scan durations.

### 4. Sigstore CI/CD Supply Chain Verification
A GitHub Actions workflow (`.github/workflows/dirtycow-lab.yml`) demonstrating automated DevSecOps practices: AquaSec Trivy vulnerability scanning and keyless container signing via Sigstore Cosign and GitHub Actions OIDC.

## Usage

### Build the Lab Environment
```bash
docker build -t dirtycow-lab .
```

### Run the Interactive Demo
The orchestration script (`run_demo.sh`) guides you through all four attack stages and their corresponding mitigations.
```bash
docker run -it --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --cap-add=SYS_PTRACE --pid=host \
  dirtycow-lab
```

### Run the Benchmark Suite
To generate statistical data on the performance overhead of the various security mechanisms:
```bash
./benchmark.sh
```

## Security Notice
This repository contains active exploit code and deliberately vulnerable configurations. **DO NOT run these commands on production systems or un-sandboxed environments.** The tools are strictly for educational and research purposes within isolated lab environments.
