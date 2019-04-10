#include <stdlib.h>
#include <gc.h>

typedef union licp {
    int i;
    struct func {
        union licp *vars;
        union licp (*f)(union licp *vars);
        int n;
    } f;
    struct list {
        union licp *vals;
        int n;
    } l;
} LICP;

void *alloc(size_t size) {
    return GC_malloc(size);
}
