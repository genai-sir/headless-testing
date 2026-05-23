# Builds binder_linux.ko (multi-device) and ashmem_linux.ko for Synology DSM.
#
# Uses Google's android-4.4-p binder (kernel 4.4 + Android P multi-device)
# plus Synology kernel-tree ashmem. Both use deps.c shims for unexported symbols.

FROM debian:bookworm-slim

ARG DSM_BUILD=7.3-86009
ARG PLATFORM=geminilake

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget xz-utils ca-certificates bc kmod build-essential \
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

WORKDIR /build/linux-4.4.x

RUN cp synoconfigs/${PLATFORM} .config && \
    scripts/config --enable ANDROID && \
    scripts/config --set-str LOCALVERSION + && \
    make olddefconfig && \
    make prepare && \
    make scripts

# ── Copy deps.c shim files from build context ───────────────────────────────
COPY ashmem_deps.c /build/ashmem_deps.c
COPY binder_deps.c /build/binder_deps.c

# ── Build ashmem from kernel tree (works fine) ──────────────────────────────
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

# ── Copy android-4.4-p binder source (multi-device support) ──────────────────
# Google's backport of multi-device binder to kernel 4.4, for Android P.
COPY android-4.4-p-binder/binder.c       /build/binder/binder.c
COPY android-4.4-p-binder/binder_alloc.c /build/binder/binder_alloc.c
COPY android-4.4-p-binder/binder_alloc.h /build/binder/binder_alloc.h
COPY android-4.4-p-binder/binder_trace.h /build/binder/binder_trace.h
COPY android-4.4-p-binder/uapi/linux/android/binder.h /build/binder/uapi/linux/android/binder.h

# Replace kernel's UAPI binder.h with android-4.4-p version (adds new types).
# Safe because ashmem is already built above.
RUN cp /build/binder/uapi/linux/android/binder.h \
       /build/linux-4.4.x/include/uapi/linux/android/binder.h

# Patch for module compilation.
RUN sed -i '1i #include <linux/module.h>' /build/binder/binder.c && \
    sed -i 's/device_initcall(binder_init);/module_init(binder_init);/' /build/binder/binder.c && \
    sed -i 's/mmput_async/mmput/g' /build/binder/binder_alloc.c

# Copy deps shim.
RUN cp /build/binder_deps.c /build/binder/deps.c

COPY android-4.4-p-binder/Makefile /build/binder/Makefile

# Build binder. On failure, show errors for debugging.
RUN make -C /build/linux-4.4.x M=/build/binder EXTRA_CFLAGS="-Wno-error" modules 2>&1 \
    && echo "binder OK" \
    || { echo "=== BINDER BUILD FAILED ==="; \
         make -C /build/linux-4.4.x M=/build/binder EXTRA_CFLAGS="-Wno-error" modules 2>&1 \
           | grep -E "error:|undefined|fatal|warning:" | head -40; \
         false; }

# ── Build mmap_rnd_bits shim (needed for Android 8+ on kernel 4.4) ────────
COPY mmap_rnd_shim.c /build/mmap_rnd/mmap_rnd_shim.c
RUN printf 'obj-m := mmap_rnd_shim.o\n' > /build/mmap_rnd/Makefile && \
    make -C /build/linux-4.4.x M=/build/mmap_rnd modules && \
    echo "mmap_rnd_shim OK"

# ── Collect ──────────────────────────────────────────────────────────────────
RUN mkdir -p /out && \
    cp /build/ashmem/ashmem_linux.ko /out/ && \
    cp /build/binder/binder_multidev.ko /out/ && \
    cp /build/mmap_rnd/mmap_rnd_shim.ko /out/ && \
    echo "=== Final modules ===" && \
    ls -la /out/ && \
    modinfo /out/binder_multidev.ko && echo "---" && \
    modinfo /out/ashmem_linux.ko && echo "---" && \
    modinfo /out/mmap_rnd_shim.ko

CMD ["echo", "Modules built. Copy from /out/"]
