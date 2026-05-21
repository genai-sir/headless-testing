# Builds binder_linux.ko and ashmem_linux.ko for Synology DSM (geminilake)
# using the redroid-modules project, which provides runtime shims for
# kernel symbols that Synology doesn't export.

FROM debian:bookworm-slim

ARG DSM_BUILD=7.3-86009
ARG PLATFORM=geminilake

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget xz-utils ca-certificates bc kmod build-essential git \
    libncurses-dev libssl-dev libelf-dev bison flex cpio \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN wget -q -O toolchain.txz \
    "https://global.synologydownload.com/download/ToolChain/toolchain/${DSM_BUILD}/Intel%20x86%20Linux%204.4.302%20%28GeminiLake%29/${PLATFORM}-gcc1220_glibc236_x86_64-GPL.txz" \
    && mkdir -p /toolchain \
    && tar -xf toolchain.txz -C /toolchain \
    && rm toolchain.txz

RUN wget -q -O linux-4.4.x.txz \
    "https://global.synologydownload.com/download/ToolChain/Synology%20NAS%20GPL%20Source/${DSM_BUILD}/${PLATFORM}/linux-4.4.x.txz" \
    && tar -xf linux-4.4.x.txz \
    && rm linux-4.4.x.txz

# Clone redroid-modules (has deps.c shims for unexported Synology symbols).
RUN git clone --depth 1 https://github.com/remote-android/redroid-modules.git /build/redroid-modules

WORKDIR /build/linux-4.4.x

# Prepare the kernel tree as a module build target.
RUN cp synoconfigs/${PLATFORM} .config && \
    scripts/config --enable ANDROID && \
    scripts/config --set-str LOCALVERSION + && \
    make olddefconfig && \
    make prepare && \
    make scripts

# Build redroid-modules against the Synology kernel tree.
# KDIR points to our prepared kernel source.
WORKDIR /build/redroid-modules

RUN echo "=== Building ashmem ===" && \
    make -C /build/linux-4.4.x M=/build/redroid-modules/ashmem \
        EXTRA_CFLAGS=-Wno-error modules && \
    ls -la ashmem/ashmem_linux.ko

RUN echo "=== Building binder ===" && \
    make -C /build/linux-4.4.x M=/build/redroid-modules/binder \
        EXTRA_CFLAGS=-Wno-error modules && \
    ls -la binder/binder_linux.ko

RUN mkdir -p /out && \
    cp ashmem/ashmem_linux.ko /out/ && \
    cp binder/binder_linux.ko /out/ && \
    echo "=== Final modules ===" && \
    ls -la /out/ && \
    modinfo /out/binder_linux.ko && echo "---" && \
    modinfo /out/ashmem_linux.ko

CMD ["echo", "Modules built. Copy from /out/"]
