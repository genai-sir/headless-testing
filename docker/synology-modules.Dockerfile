# Compiles binder_linux.ko and ashmem_linux.ko for Synology DSM (geminilake).
#
# Instead of fighting Kconfig bool→tristate, we directly patch the Makefile
# to force-build binder and ashmem as modules (obj-m).
#
# Build args (override for different DSM builds):
#   DSM_BUILD  — e.g. 7.3-86009  (default, matches DS224+ on DSM 7.3.2)
#   PLATFORM   — e.g. geminilake  (default)

FROM debian:bookworm-slim

ARG DSM_BUILD=7.3-86009
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

# Use Synology's geminilake kernel config and enable the ANDROID subsystem.
RUN cp synoconfigs/${PLATFORM} .config && \
    scripts/config --enable ANDROID && \
    scripts/config --enable SHMEM && \
    scripts/config --enable MMU && \
    make olddefconfig

# Prepare kernel build infrastructure.
RUN make prepare && make scripts

# Show what's in the android staging directory (diagnostic).
RUN echo "--- Makefile ---" && \
    cat drivers/staging/android/Makefile && \
    echo "--- Source files ---" && \
    ls drivers/staging/android/*.c

# Force-patch the Makefile so binder and ashmem are built as modules (obj-m)
# regardless of the Kconfig bool settings.
RUN sed -i 's/obj-$(CONFIG_ANDROID_BINDER_IPC)/obj-m/' drivers/staging/android/Makefile && \
    sed -i 's/obj-$(CONFIG_ASHMEM)/obj-m/' drivers/staging/android/Makefile && \
    echo "--- Patched Makefile ---" && \
    cat drivers/staging/android/Makefile

# Build the modules.
RUN make M=drivers/staging/android modules

# Show what was built.
RUN echo "--- Built .ko files ---" && \
    find drivers/staging/android/ -name "*.ko" -exec ls -la {} \;

# Copy and normalize names → binder_linux.ko / ashmem_linux.ko
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

RUN modinfo /out/binder_linux.ko && echo "---" && modinfo /out/ashmem_linux.ko

CMD ["echo", "Modules built. Copy from /out/"]
