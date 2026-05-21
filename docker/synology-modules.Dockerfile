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

# ── Prepare out-of-tree build directories ────────────────────────────────────

# Copy ashmem source to a standalone build directory.
RUN mkdir -p /build/ashmem && \
    cp drivers/staging/android/ashmem.c /build/ashmem/ && \
    cp drivers/staging/android/ashmem.h /build/ashmem/ 2>/dev/null || true && \
    cp drivers/staging/android/uapi/ashmem.h /build/ashmem/uapi_ashmem.h 2>/dev/null || true

# Copy binder source. It's in drivers/android/ on this kernel.
RUN BINDER_DIR=$(dirname $(find drivers/ -path "*/android/binder.c" | head -1)) && \
    echo "Binder at: $BINDER_DIR" && \
    mkdir -p /build/binder && \
    cp "$BINDER_DIR"/binder.c /build/binder/ && \
    cp "$BINDER_DIR"/binder_trace.h /build/binder/ 2>/dev/null || true && \
    find "$BINDER_DIR" -name "*.h" -exec cp {} /build/binder/ \; 2>/dev/null || true

# ── Create deps.c shims for unexported Synology kernel symbols ───────────────

RUN cat > /build/ashmem/deps.c << 'DEPS_EOF'
#include <linux/mm.h>
#include <linux/kallsyms.h>
#include <linux/module.h>

typedef int (*shmem_zero_setup_ptr_t)(struct vm_area_struct *);
static shmem_zero_setup_ptr_t shmem_zero_setup_ptr = NULL;
int shmem_zero_setup(struct vm_area_struct *vma)
{
    if (!shmem_zero_setup_ptr)
        shmem_zero_setup_ptr = (shmem_zero_setup_ptr_t)kallsyms_lookup_name("shmem_zero_setup");
    return shmem_zero_setup_ptr(vma);
}
DEPS_EOF

RUN cat > /build/binder/deps.c << 'DEPS_EOF'
#include <linux/sched.h>
#include <linux/file.h>
#include <linux/fdtable.h>
#include <linux/mm.h>
#include <linux/kallsyms.h>
#include <linux/module.h>

typedef struct sighand_struct *(*__lock_task_sighand_ptr_t)(struct task_struct *, unsigned long *);
static __lock_task_sighand_ptr_t __lock_task_sighand_ptr = NULL;
struct sighand_struct *__lock_task_sighand(struct task_struct *tsk, unsigned long *flags)
{
    if (!__lock_task_sighand_ptr)
        __lock_task_sighand_ptr = (__lock_task_sighand_ptr_t)kallsyms_lookup_name("__lock_task_sighand");
    return __lock_task_sighand_ptr(tsk, flags);
}

typedef struct files_struct *(*get_files_struct_ptr_t)(struct task_struct *);
static get_files_struct_ptr_t get_files_struct_ptr = NULL;
struct files_struct *get_files_struct(struct task_struct *task)
{
    if (!get_files_struct_ptr)
        get_files_struct_ptr = (get_files_struct_ptr_t)kallsyms_lookup_name("get_files_struct");
    return get_files_struct_ptr(task);
}

typedef int (*__alloc_fd_ptr_t)(struct files_struct *, unsigned, unsigned, unsigned);
static __alloc_fd_ptr_t __alloc_fd_ptr = NULL;
int __alloc_fd(struct files_struct *files, unsigned start, unsigned end, unsigned flags)
{
    if (!__alloc_fd_ptr)
        __alloc_fd_ptr = (__alloc_fd_ptr_t)kallsyms_lookup_name("__alloc_fd");
    return __alloc_fd_ptr(files, start, end, flags);
}

typedef int (*can_nice_ptr_t)(const struct task_struct *, const int);
static can_nice_ptr_t can_nice_ptr = NULL;
int can_nice(const struct task_struct *p, const int nice)
{
    if (!can_nice_ptr)
        can_nice_ptr = (can_nice_ptr_t)kallsyms_lookup_name("can_nice");
    return can_nice_ptr(p, nice);
}
DEPS_EOF

# ── Patch ashmem for module compilation ──────────────────────────────────────

RUN sed -i '1i #include <linux/module.h>' /build/ashmem/ashmem.c && \
    sed -i 's/device_initcall(ashmem_init);/module_init(ashmem_init);\nMODULE_LICENSE("GPL");/' \
        /build/ashmem/ashmem.c

RUN cat > /build/ashmem/Makefile << 'MK_EOF'
ccflags-y += -I$(src) -I$(KDIR)/drivers/staging/android
obj-m := ashmem_linux.o
ashmem_linux-y := ashmem.o deps.o
MK_EOF

# ── Patch binder for module compilation ──────────────────────────────────────

RUN sed -i '1i #include <linux/module.h>' /build/binder/binder.c && \
    sed -i 's/device_initcall(binder_init);/module_init(binder_init);\nMODULE_LICENSE("GPL");/' \
        /build/binder/binder.c

RUN cat > /build/binder/Makefile << 'MK_EOF'
ccflags-y += -I$(src) -DCONFIG_ANDROID_BINDER_DEVICES=\"binder,hwbinder,vndbinder\"
obj-m := binder_linux.o
binder_linux-y := binder.o deps.o
MK_EOF

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
