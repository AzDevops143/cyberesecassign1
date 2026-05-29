# Hexa Force: Complete Architecture Deep Dive

This document serves as a comprehensive reference guide for the Hexa Force architecture, detailing the 4-stage cascading failure of container isolation (The Attack) and the corresponding 8-layer defense-in-depth strategy (The Mitigation).

---

## Part 1: The Attack Architecture (Cascading Failure)

### Stage 1: The Kernel Exploit (Dirty COW)
**Vulnerability:** CVE-2016-5195 (Host Kernel Copy-on-Write bug)

The attacker maps a read-only system file into virtual memory. By concurrently calling `madvise(MADV_DONTNEED)` and writing to `/proc/self/mem`, the host kernel gets confused during the memory fault and accidentally writes the malicious payload directly to the physical, read-only file on disk. This grants the attacker root privileges *inside* the container.

```mermaid
sequenceDiagram
    participant C as Container
    participant K as Host Kernel
    participant F as Physical File
    C->>K: mmap() read-only file
    par
        C->>K: madvise(MADV_DONTNEED)
    and
        C->>K: write(/proc/self/mem)
    end
    Note over C,K: Kernel race condition triggers
    K-->>F: Malicious write succeeds on disk
```

### Stage 2: Process Injection (Namespace Bypass)
**Vulnerability:** Shared PID Namespace & `CAP_SYS_PTRACE`

With container-root achieved, the attacker leverages the shared PID namespace to "see" processes running on the underlying host. Using the `CAP_SYS_PTRACE` capability, the attacker injects malicious shellcode directly into the memory space of a privileged host daemon. The payload now executes on the host, escaping the container boundary.

```mermaid
sequenceDiagram
    participant C as Container Root
    participant NS as Shared PID Namespace
    participant H as Host Process
    C->>NS: Scan for host processes (e.g., PID 1204)
    NS-->>C: Target found
    C->>H: ptrace(ATTACH, 1204)
    C->>H: Inject Shellcode via Registers
    Note over C,H: Lateral Movement Achieved
    H-->>H: Host executes injected payload
```

### Stage 3: Docker Daemon API Hijacking
**Vulnerability:** Exposed `/var/run/docker.sock`

The attacker discovers the host's Docker Unix socket is mounted inside the container. This socket is the raw HTTP API for the entire Docker engine. By sending crafted POST requests to this socket using `curl`, the attacker gains full administrative control over the host's container orchestrator.

```mermaid
sequenceDiagram
    participant A as Attacker (Injected Payload)
    participant S as docker.sock
    participant D as Docker Engine (Host)
    A->>S: curl -X POST http://localhost/containers/create
    S->>D: Forward API Request
    Note over S,D: Attacker has raw admin control
    D-->>A: Created rogue container ID
```

### Stage 4: Persistent Host Takeover (Filesystem Pivot)
**Vulnerability:** Writable Host Mounts

Using the hijacked API from Stage 3, the attacker commands the Docker engine to spawn a new "sibling" container. Crucially, they configure this new container to mount the physical host's root directory (`/`) directly into the container. The attacker then writes a reverse shell script into the host's cron daemon folder. The physical host blindly executes this script, granting permanent control over the bare-metal server.

```mermaid
sequenceDiagram
    participant A as Attacker
    participant D as Docker Engine
    participant V as Host Volume Mount
    participant Cron as Host Cron Daemon
    A->>D: Start rogue container (mount '/' to '/mnt/host')
    D->>V: Mount physical host disk
    A->>V: echo "* * * * * root reverse_shell" > /mnt/host/etc/cron.d/pwn
    Note over V,Cron: Permanent Persistence Achieved
    Cron-->>Cron: Host executes backdoor as Root
```

---

## Part 2: The Mitigation Architecture (Hexa Force)

### Stage 1 Mitigation: Seccomp eBPF Filtering
**Action:** Injecting a Secure Computing (Seccomp) profile into the kernel's eBPF engine.

When the attacker attempts the Dirty COW exploit, the eBPF engine intercepts the `madvise` system call before it reaches the kernel's memory manager. The eBPF filter instantly drops the request, returning an `EPERM` error. The race condition is mathematically impossible to trigger.

```mermaid
sequenceDiagram
    participant C as Container (Attacker)
    participant SEC as Seccomp BPF Filter (Hexa Force)
    participant K as Host Kernel (Vulnerable)
    
    C->>SEC: 1. mmap() read-only file
    SEC-->>C: Allowed
    
    par
        C->>SEC: 2. madvise(MADV_DONTNEED)
        SEC--xK: 3. BLOCKED! (SCMP_ACT_ERRNO)
        SEC-->>C: 4. Returns "Operation not permitted" (EPERM)
    and
        C->>SEC: 5. write(/proc/self/mem)
        SEC-->>C: Allowed (harmless without madvise)
    end
```

### Stage 2 Mitigation: Capability Dropping
**Action:** Enforcing Principle of Least Privilege via `--cap-drop=ALL`.

The Linux Security Module (LSM) intercepts the attacker's `ptrace()` call. It checks the container's capability bounding set and sees that `CAP_SYS_PTRACE` is missing. The LSM kills the system call, preventing the attacker from debugging or injecting code into host processes. Lateral movement is severed.

```mermaid
sequenceDiagram
    participant C as Container (Attacker Root)
    participant SEC as Linux Security Module
    participant H as Host Process
    
    C->>SEC: 1. ptrace(PTRACE_ATTACH, 1204)
    SEC--xH: 2. BLOCKED! Capability missing
    SEC-->>C: 3. Returns "Operation not permitted" (EPERM)
```

### Stage 3 Mitigation: Socket Isolation
**Action:** Strictly forbidding the mounting of `/var/run/docker.sock`.

Because the container is trapped in its own isolated Mount Namespace, it cannot see the host's `/var/run` directory. The Docker API is physically invisible and inaccessible. The attacker cannot hijack the orchestration engine.

### Stage 4 Mitigation: Immutable Filesystems
**Action:** Deploying containers with the `--read-only` flag.

Even if the attacker somehow leverages a zero-day to mount the host disk, the kernel's Virtual File System (VFS) enforces the read-only flag. When the attacker attempts to write their cron backdoor, the VFS blocks the write at the lowest level, returning an `EROFS` (Read-only file system) error. Persistence is denied, and the host remains completely sterile.

---

## Appendix: The Role of eBPF

**eBPF (Extended Berkeley Packet Filter)** operates as a lightning-fast virtual machine embedded directly inside the host Linux Kernel. 

In the Hexa Force architecture, Docker translates our `hexaforce-seccomp.json` mitigation profile into eBPF bytecode. This bytecode is loaded into the kernel and intercepts system calls in microseconds. This allows us to surgically patch the Dirty COW vulnerability in real-time, at the kernel level, *without* rebooting the server and *without* breaking any other containers running on the same host.
