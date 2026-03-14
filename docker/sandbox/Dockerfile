# Sandbox Container Image
#
# Base image for running agent sandboxes.
# Includes common tools and security hardening.
#
# Build:
#   docker build -t sandbox-base -f docker/sandbox/Dockerfile .
#
# For Incus, convert to image:
#   docker save sandbox-base | incus image import - --alias sandbox-base
#
# Or build directly in Incus:
#   incus launch images:ubuntu/22.04 sandbox-base
#   incus exec sandbox-base -- /path/to/setup.sh
#   incus publish sandbox-base --alias sandbox-base

FROM ubuntu:22.04 AS base

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Create non-root user for sandbox execution
RUN useradd -m -s /bin/bash -u 1000 sandbox && \
    mkdir -p /home/sandbox/.local/bin && \
    chown -R sandbox:sandbox /home/sandbox

# Install base system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essential tools
    ca-certificates \
    curl \
    wget \
    git \
    # Build tools
    build-essential \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    # Node.js (via nodesource)
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install common Python packages
RUN pip3 install --no-cache-dir \
    httpx \
    aiohttp \
    requests \
    beautifulsoup4 \
    lxml

# Install common Node.js packages globally
RUN npm install -g \
    typescript \
    ts-node \
    @types/node

# Create sandbox workspace
RUN mkdir -p /workspace && chown sandbox:sandbox /workspace

# Setup minimal web server for health checks
COPY docker/sandbox/server.py /opt/sandbox/server.py
RUN chmod +x /opt/sandbox/server.py

# Switch to non-root user
USER sandbox
WORKDIR /workspace

# Health check endpoint
EXPOSE 8080

# Default command: start health server and wait
CMD ["python3", "/opt/sandbox/server.py"]

# -------------------------------------------------------------------
# Playwright variant
# -------------------------------------------------------------------
FROM base AS playwright

USER root

# Install Playwright dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Playwright system dependencies
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    libatspi2.0-0 \
    # Fonts
    fonts-liberation \
    fonts-noto-color-emoji \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER sandbox

# Install Playwright
RUN npm install playwright && \
    npx playwright install chromium

ENV PLAYWRIGHT_BROWSERS_PATH=/home/sandbox/.cache/ms-playwright

# -------------------------------------------------------------------
# Terminal variant (lightweight)
# -------------------------------------------------------------------
FROM base AS terminal

USER root

# Add terminal-specific tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    vim \
    nano \
    htop \
    jq \
    tree \
    ripgrep \
    fd-find \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER sandbox

# -------------------------------------------------------------------
# Research variant (with ML tools)
# -------------------------------------------------------------------
FROM base AS research

USER sandbox

# Install research/ML packages
RUN pip3 install --no-cache-dir \
    numpy \
    pandas \
    scikit-learn \
    matplotlib \
    seaborn \
    jupyter \
    ipython
