# Compiles binder_linux.ko and ashmem_linux.ko for Synology DSM 7.2 (geminilake).
#
# These modules let Redroid run on the DS224+ (and similar Celeron J4125 NAS models).
# The vermagic of the compiled .ko must match `uname -r` on the NAS exactly.
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

# Configure the kernel with Synology's geminilake defconfig.
RUN cp synoconfigs/${PLATFORM} .config

# Enable binder and ashmem as loadable modules.
RUN sed -i 's/.*CONFIG_ANDROID=.*/CONFIG_ANDROID=y/' .config || echo 'CONFIG_ANDROID=y' >> .config \
    && sed -i 's/.*CONFIG_ANDROID_BINDER_IPC=.*/CONFIG_ANDROID_BINDER_IPC=m/' .config || echo 'CONFIG_ANDROID_BINDER_IPC=m' >> .config \
    && sed -i 's/.*CONFIG_ASHMEM=.*/CONFIG_ASHMEM=m/' .config || echo 'CONFIG_ASHMEM=m' >> .config \
    && sed -i 's/.*CONFIG_ANDROID_BINDER_DEVICES=.*/CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"/' .config \
       || echo 'CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"' >> .config

RUN make olddefconfig

# Prepare kernel build infrastructure (generates Module.symvers, scripts, etc.)
RUN make prepare && make scripts

# Compile only the staging/android modules (binder + ashmem).
RUN make M=drivers/staging/android modules

# Verify the modules were built.
RUN ls -la drivers/staging/android/binder_linux.ko \
           drivers/staging/android/ashmem_linux.ko

# Copy built modules to /out for extraction.
RUN mkdir -p /out \
    && cp drivers/staging/android/binder_linux.ko /out/ \
    && cp drivers/staging/android/ashmem_linux.ko /out/

# Print vermagic so the user can confirm it matches their NAS kernel.
RUN modinfo /out/binder_linux.ko | head -5 \
    && modinfo /out/ashmem_linux.ko | head -5

CMD ["echo", "Modules built. Copy from /out/"]
