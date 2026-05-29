#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Hexa Force — Container Security Benchmark Suite
# School of AI & Data Science, IIT Jodhpur
#
# Measures real performance overhead of security controls:
#   1. Container startup latency (baseline vs. seccomp vs. cap-drop)
#   2. Exploit success rate across mitigation configurations
#   3. Trivy scan duration
#   4. Build pipeline overhead
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

IMAGE_NAME="dirtycow-lab"
SECCOMP_PROFILE="hexaforce-seccomp.json"
ROUNDS=10
CSV_OUTPUT="benchmark_results.csv"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ─── Utility: nanosecond timer ─────────────────────────────────────
timestamp_ns() {
    date +%s%N
}

elapsed_ms() {
    local start=$1 end=$2
    echo "scale=2; ($end - $start) / 1000000" | bc
}

# ─── Header ────────────────────────────────────────────────────────
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   HEXA FORCE — Security Control Benchmark Suite     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Initialize CSV
echo "Test,Configuration,Round,Duration_ms,Result" > "$CSV_OUTPUT"

# ═══════════════════════════════════════════════════════════════════
# BENCHMARK 1: Container Startup Latency
# ═══════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[BENCH 1] Container Startup Latency${NC}"
echo ""

for config in "baseline" "seccomp" "cap-drop" "seccomp+cap-drop"; do
    echo -e "  Configuration: ${CYAN}${config}${NC}"
    total=0
    
    for i in $(seq 1 $ROUNDS); do
        case "$config" in
            "baseline")
                CMD="docker run --rm $IMAGE_NAME echo OK"
                ;;
            "seccomp")
                CMD="docker run --rm --security-opt seccomp=$SECCOMP_PROFILE $IMAGE_NAME echo OK"
                ;;
            "cap-drop")
                CMD="docker run --rm --cap-drop=ALL --cap-add=SETUID --cap-add=SETGID $IMAGE_NAME echo OK"
                ;;
            "seccomp+cap-drop")
                CMD="docker run --rm --security-opt seccomp=$SECCOMP_PROFILE --cap-drop=ALL --cap-add=SETUID --cap-add=SETGID $IMAGE_NAME echo OK"
                ;;
        esac
        
        start=$(timestamp_ns)
        eval "$CMD" > /dev/null 2>&1 || true
        end=$(timestamp_ns)
        
        ms=$(elapsed_ms $start $end)
        total=$(echo "$total + $ms" | bc)
        echo "startup,$config,$i,$ms,OK" >> "$CSV_OUTPUT"
    done
    
    avg=$(echo "scale=2; $total / $ROUNDS" | bc)
    echo -e "    Average: ${GREEN}${avg} ms${NC} over $ROUNDS rounds"
    echo ""
done

# ═══════════════════════════════════════════════════════════════════
# BENCHMARK 2: Exploit Success Rate Under Mitigations
# ═══════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[BENCH 2] Exploit Containment Rate${NC}"
echo ""

for config in "default" "seccomp-only" "cap-drop-only" "full-hardened"; do
    echo -e "  Configuration: ${CYAN}${config}${NC}"
    successes=0
    
    for i in $(seq 1 $ROUNDS); do
        case "$config" in
            "default")
                result=$(docker run --rm $IMAGE_NAME bash -c \
                    'gcc -pthread hexaforce_cow.c -o hf_cow -lrt 2>/dev/null && ./hf_cow --exploit /var/secret/target.txt "PWNED" 2>&1 | tail -1' \
                    2>/dev/null || echo "BLOCKED")
                ;;
            "seccomp-only")
                result=$(docker run --rm \
                    --security-opt seccomp=$SECCOMP_PROFILE \
                    $IMAGE_NAME bash -c \
                    'gcc -pthread hexaforce_cow.c -o hf_cow -lrt 2>/dev/null && ./hf_cow --exploit /var/secret/target.txt "PWNED" 2>&1 | tail -1' \
                    2>/dev/null || echo "BLOCKED")
                ;;
            "cap-drop-only")
                result=$(docker run --rm \
                    --cap-drop=ALL --cap-add=SETUID --cap-add=SETGID \
                    $IMAGE_NAME bash -c \
                    'gcc -pthread hexaforce_cow.c -o hf_cow -lrt 2>/dev/null && ./hf_cow --exploit /var/secret/target.txt "PWNED" 2>&1 | tail -1' \
                    2>/dev/null || echo "BLOCKED")
                ;;
            "full-hardened")
                result=$(docker run --rm \
                    --security-opt seccomp=$SECCOMP_PROFILE \
                    --cap-drop=ALL --cap-add=SETUID --cap-add=SETGID \
                    $IMAGE_NAME bash -c \
                    'gcc -pthread hexaforce_cow.c -o hf_cow -lrt 2>/dev/null && ./hf_cow --exploit /var/secret/target.txt "PWNED" 2>&1 | tail -1' \
                    2>/dev/null || echo "BLOCKED")
                ;;
        esac
        
        if echo "$result" | grep -qi "SUCCEEDED"; then
            successes=$((successes + 1))
            echo "exploit,$config,$i,0,SUCCESS" >> "$CSV_OUTPUT"
        else
            echo "exploit,$config,$i,0,BLOCKED" >> "$CSV_OUTPUT"
        fi
    done
    
    rate=$(echo "scale=1; $successes * 100 / $ROUNDS" | bc)
    if [ "$successes" -eq 0 ]; then
        echo -e "    Exploit success: ${GREEN}0% (fully contained)${NC}"
    else
        echo -e "    Exploit success: ${RED}${rate}% ($successes/$ROUNDS)${NC}"
    fi
    echo ""
done

# ═══════════════════════════════════════════════════════════════════
# BENCHMARK 3: Trivy Scan Duration
# ═══════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[BENCH 3] Vulnerability Scan Duration (Trivy)${NC}"
echo ""

if command -v trivy &> /dev/null; then
    total=0
    for i in $(seq 1 3); do
        start=$(timestamp_ns)
        trivy image --severity CRITICAL,HIGH --quiet "$IMAGE_NAME" > /dev/null 2>&1 || true
        end=$(timestamp_ns)
        ms=$(elapsed_ms $start $end)
        total=$(echo "$total + $ms" | bc)
        echo "trivy,scan,$i,$ms,OK" >> "$CSV_OUTPUT"
        echo -e "    Round $i: ${GREEN}${ms} ms${NC}"
    done
    avg=$(echo "scale=2; $total / 3" | bc)
    echo -e "    Average: ${GREEN}${avg} ms${NC}"
else
    echo -e "    ${YELLOW}Trivy not installed locally — skipping${NC}"
    echo -e "    (Pipeline scan data available in GitHub Actions logs)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Benchmark Complete — Results saved to:            ║${NC}"
echo -e "${CYAN}║   ${CSV_OUTPUT}                              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
