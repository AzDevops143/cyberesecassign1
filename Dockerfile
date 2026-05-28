# Hardened Dockerfile configured by Hexa Force Container Security Lab
# Use Ubuntu base image
FROM ubuntu:20.04

# Avoid prompt during installations
ENV DEBIAN_FRONTEND=noninteractive

# Install essential build tools, gcc, make, capability diagnostics, and process utilities
RUN apt-get update && apt-get install -y \
    gcc \
    libc6-dev \
    make \
    curl \
    libcap2-bin \
    procps \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Create target test file for Stage 1 (Dirty COW)
RUN mkdir -p /var/secret && \
    echo "THIS_IS_A_SECRET_KEY_THAT_IS_READ_ONLY" > /var/secret/target.txt && \
    chmod 444 /var/secret/target.txt && \
    chown root:root /var/secret/target.txt

# Create simulated paths for Stage 3 (docker.sock) and Stage 4 (cron host mounts)
RUN mkdir -p /var/run && \
    touch /var/run/docker.sock && \
    chmod 660 /var/run/docker.sock && \
    chown root:root /var/run/docker.sock && \
    mkdir -p /mnt/host/etc/cron.d

# Create an unprivileged user to perform the exploit
RUN useradd -m -s /bin/bash victim

# Copy source code and demo scripts
COPY dirtyc0w.c /home/victim/dirtyc0w.c
COPY run_demo.sh /home/victim/run_demo.sh

# Change ownerships and set execute permissions
RUN chown -R victim:victim /home/victim && \
    chmod +x /home/victim/run_demo.sh

# Switch to the low-privileged user environment
USER victim
WORKDIR /home/victim

# Default to running all stages sequentially if no arguments are provided
CMD ["/bin/bash", "/home/victim/run_demo.sh", "--all"]
