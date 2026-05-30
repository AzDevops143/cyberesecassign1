# Hexa Force: Student Teaching Guide

Welcome! If you are using this document to present to your classmates, follow this script and use these analogies to explain highly complex kernel vulnerabilities in an easy-to-understand way.

---

## Part 1: The "Apartment Building" Analogy (The Hook)

*Start your presentation by explaining what a container actually is using an analogy.*

**Speaker Notes:**
> "Imagine a massive apartment building. The building itself is the **Host Server**, and the building's foundation and plumbing is the **Linux Kernel**."
> 
> "A **Virtual Machine (VM)** is like giving a tenant their own detached house. They have their own plumbing and foundation. If they break a pipe, it only floods their house."
> 
> "A **Docker Container** is like giving a tenant an apartment in the shared building. They have their own walls (Namespaces), but they *share* the building's plumbing (the Host Kernel) with everyone else. If a tenant figures out how to poison the shared water supply, the whole building goes down. That is a **Kernel Escape**."

---

## Part 2: The Evolution of Page-Cache Corruption (2016-2026)

*Explain that attackers don't invent new attacks every day; they find new ways to trigger the same old flaws.*

**Speaker Notes:**
> "For the last 10 years, attackers have loved targeting the 'Page Cache'. This is a temporary memory space where the kernel stores files to make reading them faster."
> 
> "In our lab, we demonstrate the 5 evolutionary stages of how attackers have tricked the kernel into letting them overwrite read-only files in the page cache:"
> 1. **2016 (Dirty COW):** Tricked the kernel using the `madvise` system call (telling the kernel to discard memory).
> 2. **2022 (Dirty Pipe):** Tricked the kernel using the `splice` system call (manipulating pipe buffers).
> 3. **2026 (Copy Fail):** Tricked the kernel using the `AF_ALG` cryptography sockets.
> 4. **2026 (Dirty Frag):** Tricked the kernel using IPv6 fragmentation raw sockets.
> 5. **2026 (Fragnesia):** Tricked the kernel using ESP-in-TCP subsystem options.

---

## Part 3: The 4x4 MITRE Matrix (How to Attack and Defend)

*Use Stage 5 of the lab to explain the MITRE framework.*

**Speaker Notes:**
> "Breaking into the kernel is just the *mechanism*. The actual *attack* depends on what file you choose to overwrite."
> 
> "We mapped this to the **MITRE ATT&CK Framework**. An attacker could overwrite `/etc/passwd` to escalate privileges (T1611), or `/bin/su` to hijack a binary (T1574)."
> 
> "To stop this, our Hexa Force architecture uses the **MITRE D3FEND Framework**. Instead of patching 5 different kernel bugs, we use a technology called **Seccomp (System Call Filtering)**. We build a firewall *inside* the kernel that blocks the vulnerable functions (like `madvise` or `AF_ALG`) from ever being called by the container."

---

## Part 4: Live Demonstration Script

*Charan tej will Run these exact commands on the projector in front of the class. For every stage, we first run the "Vulnerable" version, and then the "Mitigated (Hexa Force)" version to prove our defense works.*

### Stage 1: Dirty COW (CVE-2016-5195)
**1. Vulnerable Command:**
```bash
docker run -it --rm dirtycow-lab ./run_demo.sh --stage-1
```
**Say:** *"Watch as the container runs the Dirty COW exploit. Because there is no Seccomp filter, the exploit reaches the shared kernel and successfully corrupts the target file using the madvise system call."*

**2. Mitigated Command:**
```bash
docker run -it --rm --security-opt seccomp=hexaforce-seccomp.json dirtycow-lab ./run_demo.sh --stage-1
```
**Say:** *"Now we load the Hexa Force Seccomp profile. Watch as the attack instantly fails with a Permission Denied error, because our firewall blocked the madvise system call."*


### Stage 1B: Dirty Pipe (CVE-2022-0847)
**1. Vulnerable Command:**
```bash
docker run -it --rm dirtycow-lab ./run_demo.sh --stage-1b
```
**Say:** *"Next is Dirty Pipe from 2022. The attacker uses the 'splice' system call to link a read-only file to a network pipe. The kernel forgets to clear the pipe's memory flags, causing corruption."*

**2. Mitigated Command:**
```bash
docker run -it --rm --security-opt seccomp=hexaforce-seccomp.json dirtycow-lab ./run_demo.sh --stage-1b
```
**Say:** *"With Hexa Force enabled, we block the splice command entirely. The malicious pipe link is never created."*


### Stage 1C: Copy Fail (CVE-2026-31431)
**1. Vulnerable Command:**
```bash
docker run -it --rm dirtycow-lab ./run_demo.sh --stage-1c
```
**Say:** *"This is a 2026 threat. The container opens a cryptographic socket (AF_ALG) and triggers a memory allocation bug in the kernel's crypto engine."*

**2. Mitigated Command:**
```bash
docker run -it --rm --security-opt seccomp=hexaforce-seccomp.json dirtycow-lab ./run_demo.sh --stage-1c
```
**Say:** *"Hexa Force deep-inspects the socket arguments. It detects the AF_ALG protocol and denies access, stopping the attack at the firewall level."*


### Stage 1D: Dirty Frag (CVE-2026-43284)
**1. Vulnerable Command:**
```bash
docker run -it --rm --cap-add=NET_RAW dirtycow-lab ./run_demo.sh --stage-1d
```
**Say:** *"Here, the attacker uses RAW IPv6 sockets to send malformed, fragmented packets. The kernel miscalculates the reassembly and overflows into the page cache."*

**2. Mitigated Command:**
```bash
docker run -it --rm --security-opt seccomp=hexaforce-seccomp.json dirtycow-lab ./run_demo.sh --stage-1d
```
**Say:** *"Our Seccomp profile drops the packets by strictly forbidding the AF_INET6 protocol on RAW sockets. The kernel never receives the malformed data."*


### Stage 1E: Fragnesia (CVE-2026-46300)
**1. Vulnerable Command:**
```bash
docker run -it --rm dirtycow-lab ./run_demo.sh --stage-1e
```
**Say:** *"The attacker creates a TCP socket and forces the kernel to attach an ESP security protocol to it, triggering a context-switch memory leak."*

**2. Mitigated Command:**
```bash
docker run -it --rm --security-opt seccomp=hexaforce-seccomp.json dirtycow-lab ./run_demo.sh --stage-1e
```
**Say:** *"Hexa Force inspects the 'setsockopt' command. It allows normal network traffic but strictly blocks the TCP_ULP option, neutralizing the leak."*


### Stage 2: Namespace & Capabilities Isolation
**1. Vulnerable Command:**
```bash
docker run -it --rm --pid=host --cap-add=SYS_PTRACE dirtycow-lab ./run_demo.sh --stage-2
```
**Say:** *"This is a configuration exploit. The container was granted excessive 'SYS_PTRACE' debugging capabilities. Watch as the attacker attaches a debugger to the Host's PID 1 and injects root shellcode."*

**2. Mitigated Command:**
```bash
docker run -it --rm --pid=host --cap-drop=SYS_PTRACE dirtycow-lab ./run_demo.sh --stage-2
```
**Say:** *"By enforcing the Principle of Least Privilege and dropping the SYS_PTRACE capability, the attacker's debugger is rejected by the kernel."*


### Stage 3: Daemon API Security
**1. Vulnerable Command:**
```bash
docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock dirtycow-lab ./run_demo.sh --stage-3
```
**Say:** *"The administrator accidentally mounted the Docker API socket into the container. The attacker sends a simple HTTP command to this socket and forces the host to spawn a rogue, fully-privileged backdoor container."*

**2. Mitigated Command:**
```bash
docker run -it --rm dirtycow-lab ./run_demo.sh --stage-3
```
**Say:** *"The mitigation is structural. By removing the socket mount completely, the API connection fails instantly. The host is unreachable."*


### Stage 4: Persistent Mounts & Filesystem
**1. Vulnerable Command:**
```bash
docker run -it --rm -v /etc/cron.d:/mnt/host/etc/cron.d dirtycow-lab ./run_demo.sh --stage-4
```
**Say:** *"The container has read/write access to a host directory. The attacker writes a malicious cron job file, and the host's operating system executes it automatically a minute later."*

**2. Mitigated Command:**
```bash
docker run -it --rm -v /etc/cron.d:/mnt/host/etc/cron.d:ro dirtycow-lab ./run_demo.sh --stage-4
```
**Say:** *"We enforce an immutable infrastructure by appending ':ro' (Read-Only) to the mount flag. The attacker's write attempt is blocked at the filesystem level."*


### Stage 5: The MITRE 4x4 Matrix
**1. Vulnerable Command:**
```bash
docker run -it --rm dirtycow-lab ./run_demo.sh --stage-5
```
**Say:** *"Finally, this is Stage 5. Watch as the orchestration script loops the Dirty COW exploit 4 times, targeting 4 different files to demonstrate Privilege Escalation, Credential Access, Persistence, and Impact on the MITRE matrix."*

**2. Mitigated Command:**
```bash
docker run -it --rm --security-opt seccomp=hexaforce-seccomp.json dirtycow-lab ./run_demo.sh --stage-5
```
**Say:** *"By loading the Hexa Force Seccomp profile one last time, you can see that securing the fundamental architectural layer neutralizes all 4 MITRE tactics simultaneously!"*
