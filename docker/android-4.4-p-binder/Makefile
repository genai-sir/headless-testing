ccflags-y += -I$(src) -DCONFIG_ANDROID_BINDER_IPC \
  -DCONFIG_ANDROID_BINDER_DEVICES=\"binder,hwbinder,vndbinder\"
obj-m := binder_multidev.o
binder_multidev-y := binder.o binder_alloc.o deps.o
