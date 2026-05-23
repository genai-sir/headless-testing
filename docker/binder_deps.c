#include <linux/sched.h>
#include <linux/file.h>
#include <linux/fdtable.h>
#include <linux/mm.h>
#include <linux/mm_types.h>
#include <linux/vmalloc.h>
#include <linux/kallsyms.h>
#include <linux/module.h>
#include <linux/cred.h>
#include <linux/security.h>
#include <linux/shrinker.h>
#include <linux/pagemap.h>

typedef struct sighand_struct *(*__lock_task_sighand_ptr_t)(struct task_struct *, unsigned long *);
static __lock_task_sighand_ptr_t __lock_task_sighand_ptr;
struct sighand_struct *__lock_task_sighand(struct task_struct *tsk, unsigned long *flags)
{
    if (!__lock_task_sighand_ptr)
        __lock_task_sighand_ptr = (__lock_task_sighand_ptr_t)kallsyms_lookup_name("__lock_task_sighand");
    return __lock_task_sighand_ptr(tsk, flags);
}

typedef struct files_struct *(*get_files_struct_ptr_t)(struct task_struct *);
static get_files_struct_ptr_t get_files_struct_ptr;
struct files_struct *get_files_struct(struct task_struct *task)
{
    if (!get_files_struct_ptr)
        get_files_struct_ptr = (get_files_struct_ptr_t)kallsyms_lookup_name("get_files_struct");
    return get_files_struct_ptr(task);
}

typedef void (*put_files_struct_ptr_t)(struct files_struct *);
static put_files_struct_ptr_t put_files_struct_ptr;
void put_files_struct(struct files_struct *files)
{
    if (!put_files_struct_ptr)
        put_files_struct_ptr = (put_files_struct_ptr_t)kallsyms_lookup_name("put_files_struct");
    put_files_struct_ptr(files);
}

typedef int (*__alloc_fd_ptr_t)(struct files_struct *, unsigned, unsigned, unsigned);
static __alloc_fd_ptr_t __alloc_fd_ptr;
int __alloc_fd(struct files_struct *files, unsigned start, unsigned end, unsigned flags)
{
    if (!__alloc_fd_ptr)
        __alloc_fd_ptr = (__alloc_fd_ptr_t)kallsyms_lookup_name("__alloc_fd");
    return __alloc_fd_ptr(files, start, end, flags);
}

typedef void (*__fd_install_ptr_t)(struct files_struct *, unsigned int, struct file *);
static __fd_install_ptr_t __fd_install_ptr;
void __fd_install(struct files_struct *files, unsigned int fd, struct file *file)
{
    if (!__fd_install_ptr)
        __fd_install_ptr = (__fd_install_ptr_t)kallsyms_lookup_name("__fd_install");
    __fd_install_ptr(files, fd, file);
}

typedef int (*__close_fd_ptr_t)(struct files_struct *, unsigned);
static __close_fd_ptr_t __close_fd_ptr;
int __close_fd(struct files_struct *files, unsigned fd)
{
    if (!__close_fd_ptr)
        __close_fd_ptr = (__close_fd_ptr_t)kallsyms_lookup_name("__close_fd");
    return __close_fd_ptr(files, fd);
}

typedef int (*can_nice_ptr_t)(const struct task_struct *, const int);
static can_nice_ptr_t can_nice_ptr;
int can_nice(const struct task_struct *p, const int nice)
{
    if (!can_nice_ptr)
        can_nice_ptr = (can_nice_ptr_t)kallsyms_lookup_name("can_nice");
    return can_nice_ptr(p, nice);
}

typedef void (*zap_page_range_ptr_t)(struct vm_area_struct *, unsigned long, unsigned long, struct zap_details *);
static zap_page_range_ptr_t zap_page_range_ptr;
void zap_page_range(struct vm_area_struct *vma, unsigned long address, unsigned long size, struct zap_details *details)
{
    if (!zap_page_range_ptr)
        zap_page_range_ptr = (zap_page_range_ptr_t)kallsyms_lookup_name("zap_page_range");
    zap_page_range_ptr(vma, address, size, details);
}

typedef struct vm_struct *(*get_vm_area_ptr_t)(unsigned long, unsigned long);
static get_vm_area_ptr_t get_vm_area_ptr;
struct vm_struct *get_vm_area(unsigned long size, unsigned long flags)
{
    if (!get_vm_area_ptr)
        get_vm_area_ptr = (get_vm_area_ptr_t)kallsyms_lookup_name("get_vm_area");
    return get_vm_area_ptr(size, flags);
}

typedef int (*map_kernel_range_noflush_ptr_t)(unsigned long, unsigned long, pgprot_t, struct page **);
static map_kernel_range_noflush_ptr_t map_kernel_range_noflush_ptr;
int map_kernel_range_noflush(unsigned long start, unsigned long size, pgprot_t prot, struct page **pages)
{
    if (!map_kernel_range_noflush_ptr)
        map_kernel_range_noflush_ptr = (map_kernel_range_noflush_ptr_t)kallsyms_lookup_name("map_kernel_range_noflush");
    return map_kernel_range_noflush_ptr(start, size, prot, pages);
}

typedef void (*__wake_up_pollfree_ptr_t)(wait_queue_head_t *);
static __wake_up_pollfree_ptr_t __wake_up_pollfree_ptr;
void __wake_up_pollfree(wait_queue_head_t *wq_head)
{
    if (!__wake_up_pollfree_ptr)
        __wake_up_pollfree_ptr = (__wake_up_pollfree_ptr_t)kallsyms_lookup_name("__wake_up_pollfree");
    __wake_up_pollfree_ptr(wq_head);
}

typedef int (*security_binder_set_context_mgr_ptr_t)(const struct cred *);
static security_binder_set_context_mgr_ptr_t security_binder_set_context_mgr_ptr;
int security_binder_set_context_mgr(const struct cred *mgr)
{
    if (!security_binder_set_context_mgr_ptr)
        security_binder_set_context_mgr_ptr = (security_binder_set_context_mgr_ptr_t)kallsyms_lookup_name("security_binder_set_context_mgr");
    return security_binder_set_context_mgr_ptr(mgr);
}

typedef int (*security_binder_transaction_ptr_t)(const struct cred *, const struct cred *);
static security_binder_transaction_ptr_t security_binder_transaction_ptr;
int security_binder_transaction(const struct cred *from, const struct cred *to)
{
    if (!security_binder_transaction_ptr)
        security_binder_transaction_ptr = (security_binder_transaction_ptr_t)kallsyms_lookup_name("security_binder_transaction");
    return security_binder_transaction_ptr(from, to);
}

typedef int (*security_binder_transfer_binder_ptr_t)(const struct cred *, const struct cred *);
static security_binder_transfer_binder_ptr_t security_binder_transfer_binder_ptr;
int security_binder_transfer_binder(const struct cred *from, const struct cred *to)
{
    if (!security_binder_transfer_binder_ptr)
        security_binder_transfer_binder_ptr = (security_binder_transfer_binder_ptr_t)kallsyms_lookup_name("security_binder_transfer_binder");
    return security_binder_transfer_binder_ptr(from, to);
}

typedef int (*security_binder_transfer_file_ptr_t)(const struct cred *, const struct cred *, struct file *);
static security_binder_transfer_file_ptr_t security_binder_transfer_file_ptr;
int security_binder_transfer_file(const struct cred *from, const struct cred *to, struct file *file)
{
    if (!security_binder_transfer_file_ptr)
        security_binder_transfer_file_ptr = (security_binder_transfer_file_ptr_t)kallsyms_lookup_name("security_binder_transfer_file");
    return security_binder_transfer_file_ptr(from, to, file);
}

typedef void (*unmap_kernel_range_ptr_t)(unsigned long, unsigned long);
static unmap_kernel_range_ptr_t unmap_kernel_range_ptr;
void unmap_kernel_range(unsigned long addr, unsigned long size)
{
    if (!unmap_kernel_range_ptr)
        unmap_kernel_range_ptr = (unmap_kernel_range_ptr_t)kallsyms_lookup_name("unmap_kernel_range");
    unmap_kernel_range_ptr(addr, size);
}

typedef void (*lru_add_drain_ptr_t)(void);
static lru_add_drain_ptr_t lru_add_drain_ptr;
void lru_add_drain(void)
{
    if (!lru_add_drain_ptr)
        lru_add_drain_ptr = (lru_add_drain_ptr_t)kallsyms_lookup_name("lru_add_drain");
    lru_add_drain_ptr();
}

typedef void (*__lru_cache_add_ptr_t)(struct page *);
static __lru_cache_add_ptr_t __lru_cache_add_ptr;
void __lru_cache_add(struct page *page)
{
    if (!__lru_cache_add_ptr)
        __lru_cache_add_ptr = (__lru_cache_add_ptr_t)kallsyms_lookup_name("__lru_cache_add");
    __lru_cache_add_ptr(page);
}

typedef int (*register_shrinker_ptr_t)(struct shrinker *);
static register_shrinker_ptr_t register_shrinker_ptr;
int register_shrinker(struct shrinker *shrinker)
{
    if (!register_shrinker_ptr)
        register_shrinker_ptr = (register_shrinker_ptr_t)kallsyms_lookup_name("register_shrinker");
    return register_shrinker_ptr(shrinker);
}

typedef void (*unregister_shrinker_ptr_t)(struct shrinker *);
static unregister_shrinker_ptr_t unregister_shrinker_ptr;
void unregister_shrinker(struct shrinker *shrinker)
{
    if (!unregister_shrinker_ptr)
        unregister_shrinker_ptr = (unregister_shrinker_ptr_t)kallsyms_lookup_name("unregister_shrinker");
    unregister_shrinker_ptr(shrinker);
}

typedef int (*shmem_read_mapping_page_gfp_ptr_t)(struct address_space *, pgoff_t, gfp_t);
static shmem_read_mapping_page_gfp_ptr_t shmem_read_mapping_page_gfp_ptr;
struct page *shmem_read_mapping_page_gfp(struct address_space *mapping, pgoff_t index, gfp_t gfp)
{
    if (!shmem_read_mapping_page_gfp_ptr)
        shmem_read_mapping_page_gfp_ptr = (shmem_read_mapping_page_gfp_ptr_t)kallsyms_lookup_name("shmem_read_mapping_page_gfp");
    return (struct page *)shmem_read_mapping_page_gfp_ptr(mapping, index, gfp);
}

typedef struct mm_struct *(*get_task_mm_ptr_t)(struct task_struct *);
static get_task_mm_ptr_t get_task_mm_ptr;
struct mm_struct *get_task_mm(struct task_struct *task)
{
    if (!get_task_mm_ptr)
        get_task_mm_ptr = (get_task_mm_ptr_t)kallsyms_lookup_name("get_task_mm");
    return get_task_mm_ptr(task);
}

typedef void (*mmput_ptr_t)(struct mm_struct *);
static mmput_ptr_t mmput_ptr;
void mmput(struct mm_struct *mm)
{
    if (!mmput_ptr)
        mmput_ptr = (mmput_ptr_t)kallsyms_lookup_name("mmput");
    mmput_ptr(mm);
}

#include <linux/capability.h>
typedef bool (*has_capability_noaudit_ptr_t)(struct task_struct *, int);
static has_capability_noaudit_ptr_t has_capability_noaudit_ptr;
bool has_capability_noaudit(struct task_struct *t, int cap)
{
    if (!has_capability_noaudit_ptr)
        has_capability_noaudit_ptr = (has_capability_noaudit_ptr_t)kallsyms_lookup_name("has_capability_noaudit");
    return has_capability_noaudit_ptr(t, cap);
}
