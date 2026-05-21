# Compiles binder_linux.ko and ashmem_linux.ko for Synology DSM 7.2 (geminilake).
#
# In kernel 4.4.x, binder and ashmem are bool (built-in only). We patch them
# to tristate so they can be compiled as loadable modules (.ko).
#
# Build args (override for different DSM builds):
#   DSM_BUILD  — e.g. 7.2-72806  (default)
#   PLATFORM   — e.g. geminilake  (default)

FROM debian:bookworm-slim

ARG DSM_BUILD=7.2-72806
ARG PLATFORM=geminilake

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget xz-utils ca-certificates bc kmod build-essential \
    libncurses-dev libssl-dev libelf-dev bison flex cpio \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Download Synology x86_64 toolchain for geminilake.
RUN wget -q -O toolchain.txz \
    "https://global.synologydownload.com/download/ToolChain/toolchain/${DSM_BUILD}/Intel%20x86%20Linux%204.4.302%20%28GeminiLake%29/${PLATFORM}-gcc1220_glibc236_x86_64-GPL.txz" \
    && mkdir -p /toolchain \
    && tar -xf toolchain.txz -C /toolchain \
    && rm toolchain.txz

# Download Synology GPL kernel source for geminilake.
RUN wget -q -O linux-4.4.x.txz \
    "https://global.synologydownload.com/download/ToolChain/Synology%20NAS%20GPL%20Source/${DSM_BUILD}/${PLATFORM}/linux-4.4.x.txz" \
    && tar -xf linux-4.4.x.txz \
    && rm linux-4.4.x.txz

WORKDIR /build/linux-4.4.x

# Patch Kconfig: change binder and ashmem from bool → tristate so they can
# be built as loadable modules instead of only built-in.
RUN sed -i 's/bool "Enable the Anonymous Shared Memory Subsystem"/tristate "Enable the Anonymous Shared Memory Subsystem"/' \
        drivers/staging/android/Kconfig && \
    sed -i 's/bool "Android Binder IPC Driver"/tristate "Android Binder IPC Driver"/' \
        drivers/staging/android/Kconfig && \
    echo "--- Patched Kconfig (binder + ashmem → tristate) ---"

# Start from Synology's geminilake defconfig.
RUN cp synoconfigs/${PLATFORM} .config

# Use scripts/config (reliable) to enable binder + ashmem as modules.
RUN scripts/config --enable ANDROID && \
    scripts/config --module ANDROID_BINDER_IPC && \
    scripts/config --module ASHMEM && \
    scripts/config --set-str ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder"

RUN make olddefconfig

# Verify the config took effect.
RUN echo "--- Kernel config check ---" && \
    grep CONFIG_ANDROID= .config && \
    grep CONFIG_ANDROID_BINDER_IPC .config && \
    grep CONFIG_ASHMEM .config && \
    grep CONFIG_ANDROID_BINDER_DEVICES .config

# Prepare kernel build infrastructure.
RUN make prepare && make scripts

# Compile only the staging/android modules.
RUN make M=drivers/staging/android modules

# List whatever .ko files were produced (names vary by kernel version).
RUN echo "--- Built modules ---" && \
    find drivers/staging/android/ -name "*.ko" -exec ls -la {} \;

# Copy and normalize module names (kernel 4.4.x produces binder.ko / ashmem.ko,
# but redroid and modprobe expect binder_linux.ko / ashmem_linux.ko).
RUN mkdir -p /out && \
    for ko in drivers/staging/android/*.ko; do \
      base=$(basename "$ko"); \
      case "$base" in \
        binder_linux.ko) cp "$ko" /out/binder_linux.ko ;; \
        binder.ko)       cp "$ko" /out/binder_linux.ko ;; \
        ashmem_linux.ko) cp "$ko" /out/ashmem_linux.ko ;; \
        ashmem.ko)       cp "$ko" /out/ashmem_linux.ko ;; \
        *)               cp "$ko" /out/ ;; \
      esac; \
    done && \
    ls -la /out/

# Print vermagic so the user can confirm it matches uname -r on the NAS.
RUN modinfo /out/binder_linux.ko && echo "---" && modinfo /out/ashmem_linux.ko

CMD ["echo", "Modules built. Copy from /out/"]
