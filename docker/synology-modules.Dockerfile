# Compiles binder_linux.ko and ashmem_linux.ko for Synology DSM (geminilake).
#
# The kernel 4.4.302 source has binder/ashmem as built-in only (bool, uses
# device_initcall). We patch the sources and Makefiles to build them as
# loadable modules (obj-m, module_init).

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

# Configure kernel and prepare build infrastructure.
# LOCALVERSION=+ matches the NAS kernel's uname -r suffix (4.4.302+).
RUN cp synoconfigs/${PLATFORM} .config && \
    scripts/config --enable ANDROID && \
    scripts/config --enable SHMEM && \
    scripts/config --enable MMU && \
    scripts/config --set-str LOCALVERSION + && \
    make olddefconfig && \
    echo "kernelrelease: $(make kernelrelease 2>/dev/null)" && \
    make prepare && \
    make scripts

# Find where binder and ashmem live in this kernel tree.
RUN echo "=== Locating binder ===" && \
    find drivers/ -name "binder.c" -o -name "binder_linux.c" | head -10 && \
    echo "=== Locating ashmem ===" && \
    find drivers/ -name "ashmem.c" -o -name "ashmem_linux.c" | head -10

# ── Build ashmem as a module ─────────────────────────────────────────────────
# Patch: add module.h, replace device_initcall with module_init, force obj-m.
# No module_exit needed — the module just needs to load at boot, never unload.
RUN sed -i '1i #include <linux/module.h>' drivers/staging/android/ashmem.c && \
    sed -i 's/device_initcall(ashmem_init);/module_init(ashmem_init);\nMODULE_LICENSE("GPL");/' \
        drivers/staging/android/ashmem.c && \
    sed -i 's/obj-$(CONFIG_ASHMEM)/obj-m/' drivers/staging/android/Makefile

RUN make M=drivers/staging/android EXTRA_CFLAGS=-Wno-error modules && \
    ls -la drivers/staging/android/ashmem.ko && \
    echo "ashmem.ko built OK"

# ── Build binder as a module ─────────────────────────────────────────────────
# Binder may be in drivers/android/ (de-staged) or drivers/staging/android/.
# Detect and build from whichever location has it.
RUN BINDER_DIR=$(dirname $(find drivers/ -path "*/android/binder.c" | head -1)) && \
    echo "Binder found in: $BINDER_DIR" && \
    echo "$BINDER_DIR" > /tmp/binder_dir

# Patch binder source: add module.h, replace device_initcall, fix Makefile.
RUN BINDER_DIR=$(cat /tmp/binder_dir) && \
    sed -i '1i #include <linux/module.h>' "$BINDER_DIR/binder.c" && \
    sed -i 's/device_initcall(binder_init);/module_init(binder_init);\nMODULE_LICENSE("GPL");/' \
        "$BINDER_DIR/binder.c" && \
    if grep -q 'CONFIG_ANDROID_BINDER_IPC' "$BINDER_DIR/Makefile"; then \
        sed -i 's/obj-$(CONFIG_ANDROID_BINDER_IPC)/obj-m/' "$BINDER_DIR/Makefile"; \
    else \
        echo 'obj-m += binder.o' >> "$BINDER_DIR/Makefile"; \
    fi && \
    cat "$BINDER_DIR/Makefile"

RUN BINDER_DIR=$(cat /tmp/binder_dir) && \
    make M="$BINDER_DIR" EXTRA_CFLAGS=-Wno-error modules && \
    ls -la "$BINDER_DIR"/*.ko && \
    echo "binder built OK"

# ── Collect and rename ───────────────────────────────────────────────────────
RUN mkdir -p /out && \
    BINDER_DIR=$(cat /tmp/binder_dir) && \
    # ashmem
    if [ -f drivers/staging/android/ashmem.ko ]; then \
        cp drivers/staging/android/ashmem.ko /out/ashmem_linux.ko; \
    elif [ -f drivers/staging/android/ashmem_linux.ko ]; then \
        cp drivers/staging/android/ashmem_linux.ko /out/ashmem_linux.ko; \
    fi && \
    # binder
    for ko in "$BINDER_DIR"/binder.ko "$BINDER_DIR"/binder_linux.ko; do \
        [ -f "$ko" ] && cp "$ko" /out/binder_linux.ko && break; \
    done && \
    echo "=== Final modules ===" && \
    ls -la /out/ && \
    modinfo /out/binder_linux.ko && echo "---" && \
    modinfo /out/ashmem_linux.ko

CMD ["echo", "Modules built. Copy from /out/"]
