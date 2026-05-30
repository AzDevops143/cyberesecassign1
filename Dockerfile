# Hexa Force Container Security Lab — Hardened Dockerfile
# School of AI & Data Science, IIT Jodhpur
#
# This container builds a controlled, instrumented environment for
# studying kernel-level container escape vectors and their mitigations.

FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build toolchain, capability diagnostics, process utilities,
# and cron (for Stage 4 cron injection simulation)
RUN apt-get update && apt-get install -y \
    gcc \
    libc6-dev \
    make \
    curl \
    libcap2-bin \
    procps \
    bc \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Create a root-owned, read-only target file for the COW exploit.
# chmod 444 = read-only for all users. The exploit attempts to
# overwrite this file despite lacking write permissions.
RUN mkdir -p /var/secret && \
    echo "THIS_IS_A_SECRET_KEY_THAT_IS_READ_ONLY" > /var/secret/target.txt && \
    chmod 444 /var/secret/target.txt && \
    chown root:root /var/secret/target.txt

# Simulate commonly misconfigured paths:
#  - /var/run/docker.sock : Stage 3 tests for exposed Docker daemon socket
#  - /mnt/host/etc/cron.d : Stage 4 tests for writable host filesystem mounts
RUN mkdir -p /var/run && \
    touch /var/run/docker.sock && \
    chmod 660 /var/run/docker.sock && \
    chown root:root /var/run/docker.sock && \
    mkdir -p /mnt/host/etc/cron.d

# Create an unprivileged user to simulate an application compromise.
# All exploit stages execute under this restricted context.
RUN useradd -m -s /bin/bash victim

# Copy the Hexa Force analysis tools and demo orchestrator
COPY hexaforce_cow.c /home/victim/hexaforce_cow.c
COPY hexaforce_pipe.c /home/victim/hexaforce_pipe.c
COPY hexaforce_copyfail.c /home/victim/hexaforce_copyfail.c
COPY run_demo.sh /home/victim/run_demo.sh
COPY benchmark.sh /home/victim/benchmark.sh

# Set ownership and executable permissions
RUN chown -R victim:victim /home/victim && \
    chmod +x /home/victim/run_demo.sh /home/victim/benchmark.sh

# Switch to the low-privileged user environment
USER victim
WORKDIR /home/victim

# Default: run all 4 stages of the security lab
CMD ["/bin/bash", "/home/victim/run_demo.sh", "--all"]
