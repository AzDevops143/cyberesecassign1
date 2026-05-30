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

*Charan tej will Run these exact commands on the projector in front of the class.*

### Step 1: Run the Unmitigated Attack
**Action:** Type the following command:
```bash
docker run -it --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --cap-add=SYS_PTRACE --pid=host \
  dirtycow-lab ./run_demo.sh --stage-1
```
**Say:** *"Watch as the container runs the Dirty COW exploit. Because there is no Seccomp filter, the exploit reaches the shared kernel and successfully corrupts the file."*

### Step 2: Run the MITRE Matrix (Stage 5)
**Action:** Type the following command:
```bash
docker run -it --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --cap-add=SYS_PTRACE --pid=host \
  --security-opt seccomp=hexaforce-seccomp.json \
  dirtycow-lab ./run_demo.sh --stage-5
```
**Say:** *"Now, we load the container with the Hexa Force Seccomp profile. Watch as the orchestration script tries 4 different MITRE attacks—Privilege Escalation, Credential Theft, Binary Hijacking, and Data Manipulation. Every single one is instantly blocked by our eBPF system call filter, proving the architecture works."*
