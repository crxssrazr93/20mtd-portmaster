/* PC profiling helper: lets any process of the same user attach (eu-stack, gdb) despite
   kernel.yama.ptrace_scope=1. Build: gcc -shared -fPIC -O2 -o ptracer_any.so ptracer_any.c */
#include <sys/prctl.h>
__attribute__((constructor)) static void allow(void) { prctl(PR_SET_PTRACER, PR_SET_PTRACER_ANY, 0, 0, 0); }
