# Hexa Force: Architecture & Mitigation Handbook

This document provides visual architectural diagrams for all 9 stages of the Hexa Force Containment Lab. 
For each stage, two diagrams are presented:
1.  **Attack Architecture:** How the vulnerability bypasses the container boundaries.
2.  **Mitigation Architecture:** How the Hexa Force architecture intercepts and neutralizes the attack.

---

## Stage 1: Dirty COW (CVE-2016-5195)
**Mechanism:** Exploits a race condition in the page cache using the `madvise` system call.

### Attack Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["madvise() Syscall"]
    B -->|Bypasses isolation| C["Host Kernel Page Cache"]
    C -->|Race Condition triggers| D["Overwrites Read-Only File (e.g. /etc/passwd)"]
    style D fill:#ffb3b3,stroke:#cc0000
```

### Mitigation Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["madvise() Syscall"]
    B --> C{"Seccomp eBPF Filter (Hexa Force)"}
    C -->|Intercepts & Evaluates| D["SCMP_ACT_ERRNO (EPERM)"]
    D -.->|Syscall Blocked| E["Host Kernel (Protected)"]
    style C fill:#b3ffcc,stroke:#00cc44
```

---

## Stage 1B: Dirty Pipe (CVE-2022-0847)
**Mechanism:** Exploits uninitialized pipe flags using the `splice` system call.

### Attack Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["splice() Syscall"]
    B -->|Injects data| C["Kernel Pipe Buffer"]
    C -->|Flags misconfigured| D["Overwrites Read-Only File"]
    style D fill:#ffb3b3,stroke:#cc0000
```

### Mitigation Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["splice() Syscall"]
    B --> C{"Seccomp eBPF Filter (Hexa Force)"}
    C -->|Intercepts & Evaluates| D["SCMP_ACT_ERRNO (EPERM)"]
    D -.->|Syscall Blocked| E["Kernel Pipe Buffer (Protected)"]
    style C fill:#b3ffcc,stroke:#00cc44
```

---

## Stage 1C: Copy Fail (CVE-2026-31431)
**Mechanism:** Exploits cryptographic subsystems using `AF_ALG` sockets.

### Attack Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["socket(AF_ALG) Syscall"]
    B -->|Binds payload| C["Kernel Crypto Module (aead)"]
    C -->|Memory corruption| D["Overwrites Page Cache"]
    style D fill:#ffb3b3,stroke:#cc0000
```

### Mitigation Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["socket(AF_ALG) Syscall"]
    B --> C{"Seccomp eBPF Filter (Hexa Force)"}
    C -->|Evaluates Argument 0 == 38| D["SCMP_ACT_ERRNO (EPERM)"]
    D -.->|Socket Creation Blocked| E["Kernel Crypto Module (Protected)"]
    style C fill:#b3ffcc,stroke:#00cc44
```

---

## Stage 1D: Dirty Frag (CVE-2026-43284)
**Mechanism:** Exploits IPv6 fragmentation logic via raw sockets.

### Attack Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["socket(AF_INET6, SOCK_RAW)"]
    B -->|Manipulates fragmentation| C["Kernel IPv6 Network Stack"]
    C -->|Race Condition| D["Overwrites Page Cache"]
    style D fill:#ffb3b3,stroke:#cc0000
```

### Mitigation Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["socket(AF_INET6, SOCK_RAW)"]
    B --> C{"Seccomp eBPF Filter (Hexa Force)"}
    C -->|Evaluates Argument 0 == 10| D["SCMP_ACT_ERRNO (EPERM)"]
    D -.->|Socket Creation Blocked| E["Kernel Network Stack (Protected)"]
    style C fill:#b3ffcc,stroke:#00cc44
```

---

## Stage 1E: Fragnesia (CVE-2026-46300)
**Mechanism:** Exploits the ESP-in-TCP Upper Layer Protocol subsystem.

### Attack Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["setsockopt(TCP_ULP, 'esp')"]
    B -->|Attaches Protocol| C["Kernel TCP Subsystem"]
    C -->|Subsystem Memory Leak| D["Overwrites Page Cache"]
    style D fill:#ffb3b3,stroke:#cc0000
```

### Mitigation Architecture
```mermaid
flowchart TD
    A["Unprivileged Container Process"] -->|Calls| B["setsockopt(TCP_ULP, 'esp')"]
    B --> C{"Seccomp eBPF Filter (Hexa Force)"}
    C -->|Evaluates Argument 2 == 31| D["SCMP_ACT_ERRNO (EPERM)"]
    D -.->|Socket Option Blocked| E["Kernel TCP Subsystem (Protected)"]
    style C fill:#b3ffcc,stroke:#00cc44
```

---

## Stage 2: Namespace & Capabilities Isolation
**Mechanism:** Exploits excessive privileges (`CAP_SYS_PTRACE`, `--pid=host`) to inject code into host processes.

### Attack Architecture
```mermaid
flowchart TD
    A["Container Root Process"] -->|Uses CAP_SYS_PTRACE| B["ptrace() Syscall"]
    B -->|Attaches to| C["Host Process (PID 1)"]
    C -->|Injects Shellcode| D["Host Compromise"]
    style D fill:#ffb3b3,stroke:#cc0000
```

### Mitigation Architecture
```mermaid
flowchart TD
    A["Container Process"] -->|Attempts| B["ptrace() Syscall"]
    B --> C{"Docker Capability Drop"}
    C -->|CAP_SYS_PTRACE Removed| D["SCMP_ACT_ERRNO (EPERM)"]
    D -.->|Process Injection Blocked| E["Host PID Space (Isolated)"]
    style C fill:#b3ffcc,stroke:#00cc44
```

---

## Stage 3: Daemon API Security
**Mechanism:** Exploits an exposed `/var/run/docker.sock` to spin up a privileged rogue container.

### Attack Architecture
```mermaid
flowchart TD
    A["Compromised Container"] -->|Connects to| B["/var/run/docker.sock"]
    B -->|Sends API Request| C["Docker Daemon (Host)"]
    C -->|Executes Request| D["Spawns Privileged Container (Root Access)"]
    style D fill:#ffb3b3,stroke:#cc0000
```

### Mitigation Architecture
```mermaid
flowchart TD
    A["Compromised Container"] -->|Attempts to Connect| B{"No Socket Mounted"}
    B -->|Connection Fails| C["ENOENT (No such file)"]
    C -.->|Daemon Isolated| D["Docker Daemon (Protected)"]
    style B fill:#b3ffcc,stroke:#00cc44
```

---

## Stage 4: Persistent Mounts & Filesystem
**Mechanism:** Exploits a writable host directory (e.g., `/etc/cron.d`) mounted into the container to achieve remote code execution on the host.

### Attack Architecture
```mermaid
flowchart TD
    A["Compromised Container"] -->|Writes payload to| B["/mnt/host/etc/cron.d"]
    B -->|File synced to Host| C["Host /etc/cron.d"]
    C -->|Host Cron Daemon reads| D["Host Remote Code Execution (Root)"]
    style D fill:#ffb3b3,stroke:#cc0000
```

### Mitigation Architecture
```mermaid
flowchart TD
    A["Compromised Container"] -->|Attempts Write| B{"Read-Only Mount (:ro)"}
    B -->|Write Blocked| C["EROFS (Read-only file system)"]
    C -.->|Payload Dropped| D["Host Filesystem (Protected)"]
    style B fill:#b3ffcc,stroke:#00cc44
```

---

## Stage 5: MITRE ATT&CK Matrix Visualization
**Mechanism:** Proves that 1 vulnerability mechanism can result in 4 distinct MITRE Tactics, mitigated by 4 D3FEND Techniques.

### 4x4 Threat Model Architecture
```mermaid
flowchart LR
    A["Vulnerability (Dirty COW)"] -->|T1611| B["Privilege Escalation (/etc/passwd)"]
    A -->|T1003| C["Credential Access (/etc/shadow)"]
    A -->|T1574| D["Persistence (/bin/su)"]
    A -->|T1565| E["Impact (/var/secret)"]

    F["D3-SCF (Seccomp)"] -.->|Blocks Syscall| A
    G["D3-FAC (AppArmor)"] -.->|Blocks File Access| B
    H["D3-LFP (Read-Only)"] -.->|Blocks Write| D
    I["D3-AI (gVisor)"] -.->|Sandboxes Kernel| A
```
