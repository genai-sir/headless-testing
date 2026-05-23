#include <linux/module.h>
#include <linux/sysctl.h>

static int mmap_rnd_bits_val = 28;
static int mmap_rnd_compat_bits_val = 16;

static struct ctl_table mmap_rnd_table[] = {
	{
		.procname	= "mmap_rnd_bits",
		.data		= &mmap_rnd_bits_val,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec,
	},
	{
		.procname	= "mmap_rnd_compat_bits",
		.data		= &mmap_rnd_compat_bits_val,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec,
	},
	{ }
};

static struct ctl_table vm_table[] = {
	{
		.procname	= "vm",
		.mode		= 0555,
		.child		= mmap_rnd_table,
	},
	{ }
};

static struct ctl_table_header *hdr;

static int __init mmap_rnd_shim_init(void)
{
	hdr = register_sysctl_table(vm_table);
	if (!hdr)
		return -ENOMEM;
	pr_info("mmap_rnd_shim: created /proc/sys/vm/mmap_rnd_bits (%d) "
		"and mmap_rnd_compat_bits (%d)\n",
		mmap_rnd_bits_val, mmap_rnd_compat_bits_val);
	return 0;
}

static void __exit mmap_rnd_shim_exit(void)
{
	if (hdr)
		unregister_sysctl_table(hdr);
	pr_info("mmap_rnd_shim: removed\n");
}

module_init(mmap_rnd_shim_init);
module_exit(mmap_rnd_shim_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Shim for missing mmap_rnd_bits sysctl on kernel 4.4");
