# Builds binder_linux.ko (multi-device) and ashmem_linux.ko for Synology DSM.
#
# Uses redroid-modules binder (multi-device support) + kernel-tree ashmem.
# Both include deps.c shims for unexported Synology kernel symbols.

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

# Clone redroid-modules for multi-device binder.
RUN git clone --depth 1 https://github.com/remote-android/redroid-modules.git /build/redroid-modules

WORKDIR /build/linux-4.4.x

RUN cp synoconfigs/${PLATFORM} .config && \
    scripts/config --enable ANDROID && \
    scripts/config --set-str LOCALVERSION + && \
    make olddefconfig && \
    make prepare && \
    make scripts

# ── Build ashmem from kernel tree (works on 4.4.x) ──────────────────────────
COPY ashmem_deps.c /build/ashmem_deps.c

RUN mkdir -p /build/ashmem/uapi && \
    cp drivers/staging/android/ashmem.c /build/ashmem/ && \
    cp drivers/staging/android/ashmem.h /build/ashmem/ 2>/dev/null || true && \
    cp drivers/staging/android/uapi/ashmem.h /build/ashmem/uapi/ 2>/dev/null || true && \
    cp /build/ashmem_deps.c /build/ashmem/deps.c

RUN sed -i '1i #include <linux/module.h>' /build/ashmem/ashmem.c && \
    sed -i 's/device_initcall(ashmem_init);/module_init(ashmem_init);\nMODULE_LICENSE("GPL");/' \
        /build/ashmem/ashmem.c

RUN printf 'ccflags-y += -I$(src) -I$(KDIR)/drivers/staging/android\nobj-m := ashmem_linux.o\nashmem_linux-y := ashmem.o deps.o\n' \
    > /build/ashmem/Makefile

RUN make -C /build/linux-4.4.x M=/build/ashmem EXTRA_CFLAGS=-Wno-error modules && \
    ls -la /build/ashmem/ashmem_linux.ko && echo "ashmem OK"

# ── Build binder from redroid-modules (multi-device support) ─────────────────
# Copy redroid-modules binder to a writable build directory.
RUN cp -r /build/redroid-modules/binder /build/binder_build

# Try building. Capture errors to diagnose.
RUN make -C /build/linux-4.4.x M=/build/binder_build \
    EXTRA_CFLAGS="-Wno-error -I/build/binder_build" modules 2>&1 \
    && echo "binder OK" \
    || { echo "=== BINDER BUILD FAILED — showing errors ==="; \
         make -C /build/linux-4.4.x M=/build/binder_build \
           EXTRA_CFLAGS="-Wno-error -I/build/binder_build" modules 2>&1 | grep -E "error:|undefined|fatal" | head -30; \
         false; }

# ── Collect ──────────────────────────────────────────────────────────────────
RUN mkdir -p /out && \
    cp /build/ashmem/ashmem_linux.ko /out/ && \
    cp /build/binder_build/binder_linux.ko /out/ && \
    echo "=== Final modules ===" && \
    ls -la /out/ && \
    modinfo /out/binder_linux.ko && echo "---" && \
    modinfo /out/ashmem_linux.ko

CMD ["echo", "Modules built. Copy from /out/"]
