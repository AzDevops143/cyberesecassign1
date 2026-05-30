# Hexa Force: Architecture & Mitigation Handbook

This document provides visual architectural sequence diagrams for all 9 stages of the Hexa Force Containment Lab. 
Sequence diagrams are used to illustrate the precise chronological order of system calls, thread execution, and kernel subsystem interactions that lead to container escapes, as well as the exact interception points of the Hexa Force mitigation architecture.
I used Mermaid coding for the architecture design

---

##   Architectural Primitives
Before reviewing the stages, it is critical to understand the boundaries of the environment:
*   **Unprivileged Container:** A heavily restricted process space (Namespaces) isolated from the rest of the system.
*   **Host Kernel:** The core operating system layer shared by *all* containers. If the kernel is compromised, all containers and the host are compromised.
*   **Page Cache:** A region of Host Kernel memory used to temporarily store disk files for faster access. This is the primary target for modern memory-corruption escapes.
*   **Seccomp eBPF:** A kernel-level firewall that filters system calls (the instructions the container sends to the kernel) before they execute.

---

## Stage 1: Dirty COW (CVE-2016-5195)
*   **Mechanism:** Exploits a race condition in the page cache using the `madvise` system call.
*   **Severity:** CVSS v3 7.8 (HIGH)
*   **Vulnerable Kernels:** Linux Kernel < 4.8.3

### Attack Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant VM as /proc/self/mem (Virtual Memory)
    participant VFS as Virtual File System (Kernel)
    participant Page as Physical Page (Read-Only)

    App->>VFS: 1. open("/usr/bin/passwd", O_RDONLY)
    VFS-->>App: File Descriptor (FD)
    App->>VM: 2. mmap(FD, MAP_PRIVATE)
    VM-->>Page: Maps file into virtual memory (Copy-On-Write)
    
    par Thread 1 (madvise)
        App->>VM: 3. madvise(MADV_DONTNEED)
        Note right of VM: Tells kernel to drop the private copy
    and Thread 2 (write)
        loop Continuous
            App->>VM: 4. write(/proc/self/mem, "malicious_payload")
            Note right of VM: Attempts to write to memory
            Note over VM,Page: THE RACE CONDITION
            VM->>Page: Kernel gets confused during COW fault resolution
        end
    end
    Page-->>Page: 5. Malicious data written to original read-only file!
```
**Explanation:** The attacker opens a read-only file and maps it into virtual memory. By rapidly telling the kernel they "don't need" the memory (`madvise`) while simultaneously trying to write to it, the kernel gets confused. This race condition causes the kernel to accidentally write the malicious data into the physical read-only file on the host.

### Mitigation Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant Seccomp as Hexa Force Seccomp Filter
    participant VM as /proc/self/mem (Virtual Memory)

    App->>Seccomp: 1. madvise(MADV_DONTNEED)
    Note over Seccomp: eBPF evaluates syscall and arguments
    Seccomp-->>App: 2. Returns SCMP_ACT_ERRNO (EPERM)
    Note over App,VM: The race condition is structurally impossible to start.
```
**Explanation:** Hexa Force uses Seccomp eBPF to monitor system calls. When it sees the container trying to use the dangerous `madvise` function, it instantly blocks it and returns a "Permission Denied" (EPERM) error. Without `madvise`, the race condition cannot begin.
*   **Mitigation Trade-off (Performance/Utility):** Blocking `madvise` entirely can degrade performance for legitimate database applications (like Redis or PostgreSQL) that use it for memory optimization.

---

## Stage 1B: Dirty Pipe (CVE-2022-0847)
*   **Mechanism:** Exploits uninitialized pipe flags using the `splice` system call.
*   **Severity:** CVSS v3 7.8 (HIGH)
*   **Vulnerable Kernels:** Linux Kernel 5.8 through 5.16.11

### Attack Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant VFS as Virtual File System (Kernel)
    participant Pipe as Kernel Pipe Buffer
    participant Page as Physical Page (Read-Only)

    App->>VFS: 1. open(target_file, O_RDONLY)
    App->>Pipe: 2. pipe() (Create anonymous pipe)
    App->>Pipe: 3. write() (Fill pipe to initialize rings)
    App->>VFS: 4. splice(target_fd, pipe_fd)
    VFS-->>Pipe: 5. Links target file page to pipe buffer
    Note over Pipe,Page: Pipe flags are not properly cleared!
    App->>Pipe: 6. write(pipe_fd, "malicious_payload")
    Pipe->>Page: 7. Kernel mistakenly writes pipe data directly to page cache!
```
**Explanation:** The attacker creates a network pipe, filling it with data to leave hidden "flags" active. They use the `splice` command to connect a read-only file to that pipe. Because the kernel forgot to clear those flags, anything written into the pipe is injected straight into the host's read-only file.

### Mitigation Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant Seccomp as Hexa Force Seccomp Filter
    participant VFS as Virtual File System (Kernel)

    App->>Seccomp: 1. splice(target_fd, pipe_fd)
    Note over Seccomp: eBPF rule matches 'splice'
    Seccomp-->>App: 2. Returns SCMP_ACT_ERRNO (EPERM)
    Note over App,VFS: The malicious link between file and pipe is never created.
```
**Explanation:** By applying a Seccomp filter that denies access to the `splice` system call, the container is physically incapable of linking the pipe buffer to the file.
*   **Mitigation Trade-off (Performance/Utility):** `splice` is heavily used for "zero-copy" network operations. Blocking it may reduce I/O throughput for high-performance web servers (like NGINX or HAProxy).

---

## Stage 1C: Copy Fail (CVE-2026-31431)
*   **Mechanism:** Exploits cryptographic subsystems using `AF_ALG` sockets.
*   **Severity:** CVSS v3 8.1 (HIGH)
*   **Vulnerable Kernels:** 2026 Kernel Branches

### Attack Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant Socket as Network Stack
    participant Crypto as Kernel Crypto API (aead)
    participant Page as Physical Page Cache

    App->>Socket: 1. socket(AF_ALG, SOCK_SEQPACKET, 0)
    Socket-->>App: 2. Returns Crypto Socket FD
    App->>Crypto: 3. bind(FD, "aead", "gcm(aes)")
    App->>Crypto: 4. accept(FD)
    App->>Crypto: 5. setsockopt(ALG_SET_KEY)
    Note over Crypto,Page: Cryptographic memory allocation flaw triggered
    Crypto->>Page: 6. Crypto operation corrupts adjacent page cache memory!
```
**Explanation:** The attacker creates a special socket (`AF_ALG`) to access the Linux kernel's internal cryptography engine. Feeding it a malicious key triggers a memory allocation bug, causing the crypto engine to overwrite adjacent page cache blocks.

### Mitigation Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant Seccomp as Hexa Force Seccomp Filter
    participant Socket as Network Stack

    App->>Seccomp: 1. socket(AF_ALG, ...)
    Note over Seccomp: Arg 0 == 38 (AF_ALG)
    Seccomp-->>App: 2. Returns SCMP_ACT_ERRNO (EPERM)
    Note over App,Socket: Container cannot access kernel crypto modules.
```
**Explanation:** Hexa Force's Seccomp profile deep-inspects the `socket` call. If it detects an attempt to create an `AF_ALG` (38) socket, it blocks it.
*   **Mitigation Trade-off (Performance/Utility):** Blocking `AF_ALG` prevents userspace applications from offloading cryptographic tasks to dedicated hardware (like AES-NI accelerators), increasing CPU load for encryption.

---

## Stage 1D: Dirty Frag (CVE-2026-43284)
*   **Mechanism:** Exploits IPv6 fragmentation logic via raw sockets.
*   **Severity:** CVSS v3 8.8 (HIGH)
*   **Vulnerable Kernels:** 2026 Kernel Branches

### Attack Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant Socket as Network Stack
    participant IPv6 as Kernel IPv6 Subsystem
    participant Page as Physical Page Cache

    App->>Socket: 1. socket(AF_INET6, SOCK_RAW, IPPROTO_IPV6)
    Socket-->>App: 2. Returns RAW IPv6 Socket FD
    App->>IPv6: 3. Send malformed fragmented packets
    Note over IPv6,Page: Kernel miscalculates fragmentation assembly boundaries
    IPv6->>Page: 4. Packet payload overflows into page cache memory!
```
**Explanation:** The attacker uses a RAW network socket to send intentionally fragmented IPv6 packets. A calculation error during kernel reassembly causes the packet data to overflow the buffer and corrupt the page cache.

### Mitigation Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant Seccomp as Hexa Force Seccomp Filter
    participant Socket as Network Stack

    App->>Seccomp: 1. socket(AF_INET6, SOCK_RAW, ...)
    Note over Seccomp: Arg 0 == 10 (AF_INET6)
    Seccomp-->>App: 2. Returns SCMP_ACT_ERRNO (EPERM)
    Note over App,Socket: Container cannot craft malformed IPv6 packets.
```
**Explanation:** Hexa Force intercepts the `socket` call and blocks argument `10` (`AF_INET6`), preventing raw IPv6 socket creation.
*   **Mitigation Trade-off (Performance/Utility):** Blocking RAW sockets prevents standard network diagnostic tools (like `ping6` or `traceroute`) from functioning inside the container.

---

## Stage 1E: Fragnesia (CVE-2026-46300)
*   **Mechanism:** Exploits the ESP-in-TCP Upper Layer Protocol subsystem.
*   **Severity:** CVSS v3 8.1 (HIGH)
*   **Vulnerable Kernels:** 2026 Kernel Branches

### Attack Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant Socket as Network Stack
    participant TCP as TCP Subsystem
    participant ULP as ESP ULP Module

    App->>Socket: 1. socket(AF_INET, SOCK_STREAM, 0)
    Socket-->>App: 2. Returns TCP Socket FD
    App->>TCP: 3. setsockopt(FD, IPPROTO_TCP, TCP_ULP, "esp")
    TCP->>ULP: 4. Kernel attaches ESP module to TCP stream
    Note over ULP: Module fails to sanitize user-space context
    ULP->>TCP: 5. Memory leak/corruption occurs during context switch!
```
**Explanation:** An attacker creates a TCP connection and forces the kernel to attach an advanced security protocol (`esp`) via `setsockopt`. A context-switching bug leaks memory into the host system.

### Mitigation Architecture
```mermaid
sequenceDiagram
    participant App as Unprivileged App (Container)
    participant Seccomp as Hexa Force Seccomp Filter
    participant TCP as TCP Subsystem

    App->>Seccomp: 1. setsockopt(..., TCP_ULP, ...)
    Note over Seccomp: Arg 2 == 31 (TCP_ULP)
    Seccomp-->>App: 2. Returns SCMP_ACT_ERRNO (EPERM)
    Note over App,TCP: ESP-in-TCP subsystem cannot be invoked.
```
**Explanation:** Hexa Force strictly denies the `TCP_ULP` option (`31`), physically barring the `esp` protocol attachment.
*   **Mitigation Trade-off (Performance/Utility):** Prevents containers from utilizing advanced in-kernel TCP offloading capabilities (like kernel TLS or IPSec encapsulation).

---

## Stage 2: Namespace & Capabilities Isolation
*   **Mechanism:** Exploits excessive privileges (`CAP_SYS_PTRACE`, `--pid=host`).
*   **Severity:** Operational Misconfiguration (CRITICAL Risk)

### Attack Architecture
```mermaid
sequenceDiagram
    participant App as Root Process (Container)
    participant Kernel as Host Kernel
    participant HostProcess as Process ID 1 (Host System)

    App->>Kernel: 1. ptrace(PTRACE_ATTACH, 1)
    Note over Kernel: Evaluates CAP_SYS_PTRACE flag
    Kernel-->>App: 2. Access Granted
    App->>Kernel: 3. ptrace(PTRACE_POKETEXT, 1, shellcode)
    Kernel->>HostProcess: 4. Writes malicious shellcode into Host PID 1 memory
    HostProcess-->>HostProcess: 5. Host executes attacker's code as root!
```
**Explanation:** A container with `SYS_PTRACE` privileges can attach a debugger to host processes (PID 1) and force them to execute malware.

### Mitigation Architecture
```mermaid
sequenceDiagram
    participant App as Root Process (Container)
    participant AppArmor as Hexa Force Docker Profile
    participant Kernel as Host Kernel

    App->>AppArmor: 1. ptrace(PTRACE_ATTACH, 1)
    Note over AppArmor: Verifies capability drop list
    AppArmor-->>App: 2. Returns EPERM (Capability Denied)
    Note over App,Kernel: Cross-namespace process injection is blocked.
```
**Explanation:** Enforcing strict Docker defaults and dropping dangerous capabilities neutralizes the attack.
*   **Mitigation Trade-off (Performance/Utility):** Developers cannot use legitimate debugging tools (`gdb`, `strace`) on running applications inside the container.

---

## Stage 3: Daemon API Security
*   **Mechanism:** Exploits an exposed `/var/run/docker.sock`.
*   **Severity:** Operational Misconfiguration (CRITICAL Risk)

### Attack Architecture
```mermaid
sequenceDiagram
    participant App as Compromised Container
    participant Sock as /var/run/docker.sock
    participant Daemon as Host Docker Daemon

    App->>Sock: 1. curl --unix-socket /var/run/docker.sock
    Sock->>Daemon: 2. POST /containers/create (Privileged: true, Binds: /:/host)
    Daemon-->>App: 3. Returns New Container ID
    App->>Sock: 4. POST /containers/{ID}/start
    Daemon->>Daemon: 5. Spawns new container with full root host access!
```
**Explanation:** An attacker sends HTTP commands to an exposed Docker socket, instructing the host to build a highly privileged backdoor container.

### Mitigation Architecture
```mermaid
sequenceDiagram
    participant App as Compromised Container
    participant Sock as /var/run/docker.sock
    participant Daemon as Host Docker Daemon

    App->>Sock: 1. curl --unix-socket /var/run/docker.sock
    Note over Sock: Hexa Force architecture removes socket mount
    Sock-->>App: 2. Returns ENOENT (No such file or directory)
    Note over App,Daemon: The host API is totally unreachable from the container.
```
**Explanation:** Architectural isolation (never mounting the socket) prevents the API connection.
*   **Mitigation Trade-off (Performance/Utility):** Prevents "Docker-in-Docker" (DinD) architectures heavily used in CI/CD pipelines (like Jenkins or GitLab runners) from functioning.

---

## Stage 4: Persistent Mounts & Filesystem
*   **Mechanism:** Exploits writable host directories (e.g., `/etc/cron.d`).
*   **Severity:** Operational Misconfiguration (HIGH Risk)

### Attack Architecture
```mermaid
sequenceDiagram
    participant App as Compromised Container
    participant Mount as /mnt/host/etc/cron.d (Shared Volume)
    participant HostCron as Host Cron Daemon

    App->>Mount: 1. echo "* * * * * root reverse_shell" > backdoor
    Note over Mount: Docker synchronizes volume to host disk
    HostCron->>Mount: 2. Reads new backdoor file on next minute tick
    HostCron-->>HostCron: 3. Executes reverse shell as host root!
```
**Explanation:** Writing a malicious file to a shared cron directory forces the host operating system to execute it automatically.

### Mitigation Architecture
```mermaid
sequenceDiagram
    participant App as Compromised Container
    participant Mount as /mnt/host/etc/cron.d (Read-Only Volume)
    participant HostCron as Host Cron Daemon

    App->>Mount: 1. echo "* * * * * root reverse_shell" > backdoor
    Note over Mount: Docker Read-Only Mount Flag (:ro) evaluated
    Mount-->>App: 2. Returns EROFS (Read-only file system)
    Note over App,HostCron: Host filesystem cannot be modified by the container.
```
**Explanation:** Applying Read-Only (`:ro`) mount flags enforces an immutable infrastructure.
*   **Mitigation Trade-off (Performance/Utility):** Applications cannot write state, logs, or cache to disk unless explicitly mapped to temporary memory (`tmpfs`), complicating stateless architectures.

---

## Stage 5: MITRE ATT&CK Matrix Visualization
*   **Mechanism:** Translating 1 Vulnerability Mechanism into 4 Distinct Attack Tactics.

### 4x4 Threat Model Architecture
```mermaid
sequenceDiagram
    participant Attacker as Attacker
    participant Vuln as Exploit Engine (e.g. Dirty COW)
    participant T1611 as /etc/passwd (Privilege Escalation)
    participant T1003 as /etc/shadow (Credential Access)
    participant T1574 as /bin/su (Persistence)
    participant T1565 as /var/secret (Impact)

    Attacker->>Vuln: Run Exploit (Target: T1611)
    Vuln->>T1611: Overwrite with root user
    Attacker->>Vuln: Run Exploit (Target: T1003)
    Vuln->>T1003: Overwrite with rogue hash
    Attacker->>Vuln: Run Exploit (Target: T1574)
    Vuln->>T1574: Overwrite with malicious shellcode
    Attacker->>Vuln: Run Exploit (Target: T1565)
    Vuln->>T1565: Corrupt critical data
```
**Explanation:** This diagram proves that "breaking the kernel" is just the first step. Depending on the targeted file, the attacker achieves entirely different operational objectives defined by the globally recognized MITRE ATT&CK framework.
