# Hexa Force: Architecture & Mitigation Handbook

This document provides visual architectural sequence diagrams for all 9 stages of the Hexa Force Containment Lab. 
Sequence diagrams are used to illustrate the precise chronological order of system calls, thread execution, and kernel subsystem interactions that lead to container escapes, as well as the exact interception points of the Hexa Force mitigation architecture.

---

## Stage 1: Dirty COW (CVE-2016-5195)
**Mechanism:** Exploits a race condition in the page cache using the `madvise` system call.

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

---

## Stage 1B: Dirty Pipe (CVE-2022-0847)
**Mechanism:** Exploits uninitialized pipe flags using the `splice` system call.

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

---

## Stage 1C: Copy Fail (CVE-2026-31431)
**Mechanism:** Exploits cryptographic subsystems using `AF_ALG` sockets.

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

---

## Stage 1D: Dirty Frag (CVE-2026-43284)
**Mechanism:** Exploits IPv6 fragmentation logic via raw sockets.

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

---

## Stage 1E: Fragnesia (CVE-2026-46300)
**Mechanism:** Exploits the ESP-in-TCP Upper Layer Protocol subsystem.

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

---

## Stage 2: Namespace & Capabilities Isolation
**Mechanism:** Exploits excessive privileges (`CAP_SYS_PTRACE`, `--pid=host`) to inject code.

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

---

## Stage 3: Daemon API Security
**Mechanism:** Exploits an exposed `/var/run/docker.sock` to hijack the host daemon.

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

---

## Stage 4: Persistent Mounts & Filesystem
**Mechanism:** Exploits a writable host directory (e.g., `/etc/cron.d`) mounted into the container.

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

---

## Stage 5: MITRE ATT&CK Matrix Visualization
**Mechanism:** 1 Vulnerability Mechanism -> 4 Distinct Attack Tactics.

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
