#include "gatt_paddles.h"
#include <cstdio>
int main() {
    if (!xb_gatt::TestAccumulator()) {
        std::fputs("FAIL: GATT accumulator\n", stderr);
        return 1;
    }
    std::puts("GATT regression tests passed (no hardware).");
    return 0;
}
