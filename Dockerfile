# ==============================================================
# # 1. Build stage — compile lemonade C++ binaries
# # ============================================================
FROM ubuntu:24.04 AS builder

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    libssl-dev \
    pkg-config \
    libdrm-dev \
    git \
    nodejs \
    npm \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY . /app
WORKDIR /app

# Build the project
RUN rm -rf build && \
    cmake --preset default && \
    cmake --build --preset default web-app

# Debug: Check build outputs
RUN echo "=== Build directory contents ===" && \
    ls -la build/ && \
    echo "=== Checking for resources ===" && \
    find build/ -name "*.json" -o -name "resources" -type d

# # ============================================================
# # 2. Dozen stage — Mesa's Vulkan driver for WSL
# # ============================================================
FROM ubuntu:24.04 AS dozen

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bison \
    build-essential \
    ca-certificates \
    flex \
    git \
    libdrm-dev \
    libexpat1-dev \
    libzstd-dev \
    ninja-build \
    pkg-config \
    python3-mako \
    python3-packaging \
    python3-venv \
    python3-yaml \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Mesa needs a newer meson than Ubuntu 24.04 packages.
RUN python3 -m venv /opt/meson && \
    /opt/meson/bin/pip install --no-cache-dir meson==1.12.1

# Only the driver and its data are kept. It is built for x86_64 alone until it
# is verified elsewhere; other architectures get the empty directories, so the
# runtime stage is the same for all of them.
RUN mkdir -p /opt/mesa-dzn/lib /opt/mesa-dzn/share/vulkan/icd.d && \
    if [ "$(uname -m)" = "x86_64" ]; then \
        git -c advice.detachedHead=false clone --depth 1 --branch mesa-26.0.8 \
            https://gitlab.freedesktop.org/mesa/mesa.git /mesa && \
        /opt/meson/bin/meson setup /mesa/build /mesa \
            --prefix=/opt/mesa-dzn --libdir=lib --buildtype=release -Dstrip=true \
            -Dvulkan-drivers=microsoft-experimental -Dgallium-drivers= -Dplatforms= \
            -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false \
            -Dgles1=disabled -Dgles2=disabled -Dllvm=disabled -Dvideo-codecs= && \
        DESTDIR=/tmp/stage ninja -C /mesa/build install && \
        cp /tmp/stage/opt/mesa-dzn/lib/libvulkan_dzn.so /opt/mesa-dzn/lib/ && \
        cp -r /tmp/stage/opt/mesa-dzn/share/. /opt/mesa-dzn/share/; \
    fi

# # ============================================================
# # 3. Runtime stage — small, clean image
# # ============================================================
FROM ubuntu:24.04

# vLLM/Triton JIT-compiles native launcher modules at runtime.
RUN apt-get update && apt-get install -y \
    build-essential \
    libcurl4 \
    curl \
    libssl3 \
    zlib1g \
    libdrm2 \
    libexpat1 \
    vulkan-tools \
    libvulkan1 \
    unzip \
    xz-utils \
    libgomp1 \
    libatomic1 \
    libreadline8 \
    && rm -rf /var/lib/apt/lists/*

# Dozen runs Vulkan on Direct3D 12, the only GPU interface a WSL container has,
# and Ubuntu's Mesa packages leave it out. The Vulkan loader skips it wherever
# Direct3D 12 is absent.
COPY --from=dozen /opt/mesa-dzn /opt/mesa-dzn
RUN mkdir -p /usr/share/vulkan/icd.d && \
    find /opt/mesa-dzn/share/vulkan/icd.d -name '*.json' \
        -exec ln -s {} /usr/share/vulkan/icd.d/ \;

# Run as an unprivileged user; lemond never needs root at runtime.
RUN useradd -r -u 10001 -s /usr/sbin/nologin lemonade

# The application directory doubles as the user's HOME so Lemonade's cache and
# config directories (plus the HuggingFace cache) resolve to writable paths.
WORKDIR /opt/lemonade
ENV HOME=/opt/lemonade

# Provide a private runtime directory so lemond can use get_runtime_dir()
RUN mkdir -p /run/lemonade && chmod 700 /run/lemonade
ENV XDG_RUNTIME_DIR=/run/lemonade

# Copy built executables and resources from builder
COPY --from=builder /app/build/lemond ./lemond
COPY --from=builder /app/build/lemonade ./lemonade
COPY --from=builder /app/build/resources ./resources

# Make executables executable
RUN chmod +x ./lemond ./lemonade

# Expose the lemond/lemonade binaries on PATH so `docker exec` users can run
# them (e.g. `lemonade list`, `lemonade pull`) without needing the full path.
ENV PATH="/opt/lemonade:${PATH}"

# Create cache directories and hand the whole tree to the unprivileged user.
RUN mkdir -p /opt/lemonade/llama/cpu \
    /opt/lemonade/llama/vulkan \
    /opt/lemonade/.config/lemonade \
    /opt/lemonade/.cache/huggingface \
    /opt/lemonade/.cache/lemonade && \
    chown -R lemonade:lemonade /opt/lemonade /run/lemonade

USER lemonade

# Expose default port
EXPOSE 13305

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:13305/live || exit 1

# Default command: start server in headless mode.
# Binds 0.0.0.0 because Docker port publishing (-p) reaches the container via
# its external interface, not loopback. Restrict exposure at run time by
# publishing to host loopback (-p 127.0.0.1:13305:13305) and/or setting
# LEMONADE_API_KEY. See docs/guide/install/docker.md.
CMD ["./lemond", "--host", "0.0.0.0"]
