#include <stdlib.h>
#include <gc.h>

typedef union licp {
    int i;
    struct func {
        union licp *vars;
        union licp (*f)(union licp *vars);
        int n;
    } f;
} LICP;

void *alloc(size_t size) {
    return GC_malloc(size);
}
