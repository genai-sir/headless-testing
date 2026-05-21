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
