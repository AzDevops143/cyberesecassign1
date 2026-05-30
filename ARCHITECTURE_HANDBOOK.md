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
**Explanation:** The attacker opens a read-only file (like passwords) and maps it into virtual memory. By rapidly telling the kernel they "don't need" the memory (madvise) while simultaneously trying to write to it in a parallel thread, the kernel gets confused. This race condition causes the kernel to accidentally write the malicious data into the actual physical read-only file on the host.

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
**Explanation:** Our Hexa Force firewall uses Seccomp eBPF to monitor all system calls. When it sees the container trying to use the dangerous `madvise` function, it instantly blocks it and returns a "Permission Denied" (EPERM) error. Without `madvise`, the race condition cannot even begin.

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
**Explanation:** The attacker creates a network pipe and fills it with data, leaving hidden "flags" active in the kernel. They then use the `splice` command to connect a read-only file to that pipe. Because the kernel forgot to clear those hidden flags, anything the attacker writes into the pipe is mistakenly injected straight into the read-only file on the host.

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
**Explanation:** By applying a Seccomp filter that completely denies access to the `splice` system call, the container is physically incapable of linking the pipe buffer to the file, neutralizing the Dirty Pipe exploit entirely.

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
**Explanation:** The attacker abuses the Linux kernel's internal cryptography engine. By creating a special socket (`AF_ALG`) and feeding it a malicious encryption key, a bug in the kernel's memory allocation causes the crypto engine to overwrite adjacent memory blocks, corrupting the host page cache.

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
**Explanation:** The Hexa Force Seccomp profile looks deep into the `socket` system call. If it detects the container trying to create a socket belonging to family `38` (which is `AF_ALG`), it immediately blocks it, cutting off access to the vulnerable crypto subsystem.

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
**Explanation:** The attacker creates a low-level RAW network socket and intentionally sends malformed, fragmented IPv6 packets to the kernel. When the kernel tries to reassemble these broken packets, a calculation error causes the packet data to overflow out of the network buffer and into the host's protected page cache memory.

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
**Explanation:** Normal containers do not need RAW IPv6 networking privileges. Hexa Force intercepts the `socket` call and blocks argument `10` (`AF_INET6`), preventing the attacker from crafting the raw packets required to trigger the overflow.

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
**Explanation:** The attacker creates a normal TCP network connection but then attempts to forcefully attach an advanced security protocol (`esp`) to the connection. A bug in how the kernel switches contexts for this protocol causes it to leak memory into the host system.

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
**Explanation:** Hexa Force uses deep argument inspection on the `setsockopt` command. It allows normal network configurations but strictly denies option `31` (`TCP_ULP`), rendering the attacker completely unable to attach the vulnerable `esp` protocol to their socket.

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
**Explanation:** If a container is launched with excessive Linux capabilities (like `SYS_PTRACE`) and shares the host's Process ID space, an attacker inside the container can literally attach a debugger to the host's core operating system processes (PID 1) and force them to execute malicious code.

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
**Explanation:** By ensuring strict Docker defaults and dropping dangerous capabilities, the container environment strips the attacker of the right to use debugging tools (`ptrace`), making it impossible to latch onto host processes.

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
**Explanation:** Sometimes administrators accidentally leave the Docker management socket inside the container. An attacker can simply talk to this socket via HTTP and command the host server to build them a brand new, highly privileged container that has total control over the host.

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
**Explanation:** The mitigation is architectural isolation. By never mounting the daemon socket into untrusted containers (or by enforcing strictly authenticated TCP/TLS sockets instead of UNIX sockets), the attacker has no physical path to communicate with the host API.

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
**Explanation:** If a container is given read/write access to sensitive host directories (like the cron job folder), the attacker can just write a text file containing malicious commands. Because the folder is shared, the host operating system immediately sees the file and executes the commands automatically.

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
**Explanation:** The Hexa Force architecture dictates that any host directories mounted into a container must use the Read-Only (`:ro`) flag. This enforces an immutable infrastructure where the attacker is physically blocked from saving their malicious cron jobs to the disk.

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
**Explanation:** This diagram proves to the classroom that "breaking the kernel" is just the first step. Depending on what file the attacker chooses to overwrite after they break the kernel, they achieve entirely different objectives within the globally recognized MITRE ATT&CK framework—from stealing passwords to destroying applications.
