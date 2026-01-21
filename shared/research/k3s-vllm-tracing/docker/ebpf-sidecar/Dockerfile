# eBPF CUDA Tracer Sidecar
# Container for tracing CUDA calls in vLLM inference workloads

FROM ubuntu:22.04

LABEL maintainer="LittleBoy Research"
LABEL description="eBPF sidecar for tracing CUDA API calls in vLLM workloads"

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install eBPF tracing tools and dependencies
RUN apt-get update && apt-get install -y \
    # eBPF tools
    bpftrace \
    bpfcc-tools \
    python3-bpfcc \
    linux-tools-common \
    linux-tools-generic \
    \
    # System utilities
    curl \
    wget \
    jq \
    procps \
    psmisc \
    kmod \
    \
    # Python and pip
    python3 \
    python3-pip \
    \
    # AWS CLI for S3 uploads
    unzip \
    less \
    groff \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Install Python packages for trace processing
RUN pip3 install --no-cache-dir \
    boto3 \
    requests

# Create directories
RUN mkdir -p /traces /scripts

# Copy tracing scripts
COPY trace-and-upload.sh /scripts/
COPY requirements.txt /scripts/

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Set working directory
WORKDIR /scripts

# Environment variables (can be overridden in K8s)
ENV TARGET_PROCESS="python"
ENV S3_BUCKET=""
ENV S3_PREFIX="k3s-vllm/"
ENV TRACE_INTERVAL="60"
ENV TRACE_DIR="/traces"
ENV UPLOAD_ENABLED="true"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD test -f /tmp/tracer-healthy || exit 1

# Run the tracing script
CMD ["/bin/bash", "/scripts/trace-and-upload.sh"]
