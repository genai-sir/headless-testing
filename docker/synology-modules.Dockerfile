# Builds binder_linux.ko and ashmem_linux.ko for Synology DSM (geminilake).
#
# Kernel 4.4.302 has binder/ashmem source but they're built-in only. We:
# 1. Patch source for module compilation (module_init, MODULE_LICENSE)
# 2. Add deps.c shims for unexported symbols (via kallsyms_lookup_name)
# 3. Build as out-of-tree modules

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

# ── Prepare ashmem out-of-tree build ─────────────────────────────────────────
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

# ── Prepare binder out-of-tree build ─────────────────────────────────────────
RUN BINDER_DIR=$(dirname $(find drivers/ -path "*/android/binder.c" | head -1)) && \
    mkdir -p /build/binder && \
    cp "$BINDER_DIR"/binder.c /build/binder/ && \
    find "$BINDER_DIR" -name "*.h" -exec cp {} /build/binder/ \; 2>/dev/null || true && \
    cp /build/binder_deps.c /build/binder/deps.c

RUN sed -i '1i #include <linux/module.h>' /build/binder/binder.c && \
    sed -i 's/device_initcall(binder_init);/module_init(binder_init);\nMODULE_LICENSE("GPL");/' \
        /build/binder/binder.c

RUN printf 'ccflags-y += -I$(src) -DCONFIG_ANDROID_BINDER_DEVICES=\\\"binder,hwbinder,vndbinder\\\"\nobj-m := binder_linux.o\nbinder_linux-y := binder.o deps.o\n' \
    > /build/binder/Makefile

# ── Build ────────────────────────────────────────────────────────────────────
RUN echo "=== Building ashmem ===" && \
    make -C /build/linux-4.4.x M=/build/ashmem EXTRA_CFLAGS=-Wno-error modules && \
    ls -la /build/ashmem/ashmem_linux.ko && \
    echo "ashmem OK"

RUN echo "=== Building binder ===" && \
    make -C /build/linux-4.4.x M=/build/binder EXTRA_CFLAGS=-Wno-error modules && \
    ls -la /build/binder/binder_linux.ko && \
    echo "binder OK"

# ── Collect ──────────────────────────────────────────────────────────────────
RUN mkdir -p /out && \
    cp /build/ashmem/ashmem_linux.ko /out/ && \
    cp /build/binder/binder_linux.ko /out/ && \
    echo "=== Final modules ===" && \
    ls -la /out/ && \
    modinfo /out/binder_linux.ko && echo "---" && \
    modinfo /out/ashmem_linux.ko

CMD ["echo", "Modules built. Copy from /out/"]
