# GPU Development Environment with all tools
FROM nvidia/cuda:12.3.1-devel-ubuntu22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    vim \
    nano \
    git \
    curl \
    wget \
    htop \
    nvtop \
    tmux \
    screen \
    build-essential \
    cmake \
    gdb \
    valgrind \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    iputils-ping \
    net-tools \
    dnsutils \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# Setup SSH
RUN mkdir -p /var/run/sshd && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Install Python packages for ML/AI
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel && \
    pip3 install --no-cache-dir \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 \
    transformers \
    accelerate \
    bitsandbytes \
    sentencepiece \
    protobuf \
    numpy \
    pandas \
    scipy \
    scikit-learn \
    matplotlib \
    seaborn \
    jupyter \
    jupyterlab \
    ipython \
    tensorboard \
    wandb \
    mlflow

# Install vLLM (for LLM inference)
RUN pip3 install --no-cache-dir vllm

# Install additional tools
RUN pip3 install --no-cache-dir \
    datasets \
    evaluate \
    peft \
    trl \
    einops \
    safetensors \
    huggingface-hub

# Setup workspace
RUN mkdir -p /workspace
WORKDIR /workspace

# Create welcome message
RUN echo '#!/bin/bash\n\
echo "========================================="\n\
echo "   GPU Development Environment Ready"\n\
echo "========================================="\n\
echo "GPU Info:"\n\
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader\n\
echo ""\n\
echo "CUDA Version: $(nvcc --version | grep release | awk \"{print \\$5}\" | cut -d\",\" -f1)"\n\
echo "Python: $(python3 --version)"\n\
echo "PyTorch: $(python3 -c \"import torch; print(torch.__version__)\")"\n\
echo "CUDA Available: $(python3 -c \"import torch; print(torch.cuda.is_available())\")"\n\
echo ""\n\
echo "Installed ML Tools:"\n\
echo "  - PyTorch with CUDA support"\n\
echo "  - Transformers (Hugging Face)"\n\
echo "  - vLLM (LLM inference engine)"\n\
echo "  - Jupyter Lab"\n\
echo "  - TensorBoard"\n\
echo "  - WandB, MLflow"\n\
echo ""\n\
echo "Workspace: /workspace"\n\
echo "========================================="\n\
' > /usr/local/bin/welcome.sh && chmod +x /usr/local/bin/welcome.sh

# Add to bashrc
RUN echo "source /usr/local/bin/welcome.sh" >> /root/.bashrc

# Expose SSH and Jupyter ports
EXPOSE 22 8888 6006

# Start script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
