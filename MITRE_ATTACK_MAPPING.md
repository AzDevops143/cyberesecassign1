# Hexa Force: MITRE ATT&CK & D3FEND Matrix Mapping

The Hexa Force Container Security Lab demonstrates the evolutionary timeline of kernel page-cache corruption vulnerabilities (Dirty COW through Fragnesia).

While the underlying exploitation *mechanism* (e.g., `madvise`, `splice`, `AF_ALG`) dictates how the kernel is compromised, the actual *attack* is defined by the **Target Payload**. 

This document outlines the **4 distinct MITRE ATT&CK Tactics** that can be achieved using a single kernel vulnerability, and maps them to the **4 MITRE D3FEND Techniques** required to mitigate them.

---

## 🔴 The 4 Attacks (MITRE ATT&CK Framework)

Once an unprivileged container process exploits a vulnerability like Dirty COW, it gains arbitrary read/write access to the host memory. The attacker can then choose 4 different paths:

### Attack 1: Privilege Escalation
* **Target:** Overwrite `/etc/passwd` to remove the root password requirement.
* **MITRE Tactic:** Privilege Escalation (`TA0004`)
* **MITRE Technique:** Escape to Host (`T1611`) & Exploitation for Privilege Escalation (`T1068`)
* **Impact:** The attacker gains a root shell on the underlying bare-metal host.

### Attack 2: Credential Access
* **Target:** Overwrite `/etc/shadow` to inject a known password hash for an existing administrator account.
* **MITRE Tactic:** Credential Access (`TA0006`)
* **MITRE Technique:** OS Credential Dumping / Modification (`T1003.008`)
* **Impact:** The attacker establishes persistent backdoor access via valid credentials.

### Attack 3: Persistence via Binary Hijacking
* **Target:** Overwrite a frequently used SUID binary (e.g., `/bin/su` or `/usr/bin/passwd`) with malicious shellcode.
* **MITRE Tactic:** Persistence (`TA0003`)
* **MITRE Technique:** Hijack Execution Flow (`T1574`)
* **Impact:** The attacker's malware is executed with root privileges every time a legitimate administrator attempts to switch users.

### Attack 4: Impact via Data Manipulation
* **Target:** Overwrite read-only application data or secret keys stored in `/var/secret/`.
* **MITRE Tactic:** Impact (`TA0040`)
* **MITRE Technique:** Data Manipulation (`T1565`)
* **Impact:** Financial data corruption, application denial of service, or cryptographic key destruction.

---

## 🟢 The 4 Mitigations (MITRE D3FEND Framework)

To secure a container environment against these 4 attacks, security engineers can deploy defense-in-depth across 4 architectural layers:

### Mitigation 1: System Call Filtering (The Hexa Force Approach)
* **MITRE D3FEND Technique:** System Call Filtering (`D3-SCF`)
* **Implementation:** Deploy Seccomp eBPF profiles to block the specific vulnerable syscalls (`madvise`, `splice`, `socket(AF_ALG)`).
* **Efficacy:** Neutralizes the vulnerability before memory corruption can begin.

### Mitigation 2: Mandatory Access Control (MAC)
* **MITRE D3FEND Technique:** File Access Control (`D3-FAC`)
* **Implementation:** Apply AppArmor or SELinux profiles that explicitly deny the container from accessing `/etc/` or `/bin/`.
* **Efficacy:** Even if the kernel exploit succeeds, the MAC layer prevents the attacker from targeting critical system files (blocking Attacks 1, 2, and 3).

### Mitigation 3: Immutable Infrastructure
* **MITRE D3FEND Technique:** Local File Permissions (`D3-LFP`)
* **Implementation:** Run the container with a read-only root filesystem (`docker run --read-only`).
* **Efficacy:** Prevents the attacker from downloading secondary payloads or dropping artifacts to disk, complicating the attack chain.

### Mitigation 4: Application Isolation / Execution Sandboxes
* **MITRE D3FEND Technique:** Application Isolation (`D3-AI`)
* **Implementation:** Utilize a user-space kernel proxy like **gVisor** or **Kata Containers**.
* **Efficacy:** The container is physically separated from the host kernel. Host kernel vulnerabilities like Dirty COW are 100% unreachable.
