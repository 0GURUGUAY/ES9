#include "GateState.h"
#include <stdatomic.h>
#include <stdlib.h>

struct ES9GateState {
    atomic_bool high;
    atomic_bool lowRendered;
};

ES9GateState *ES9GateStateCreate(void) {
    ES9GateState *state = malloc(sizeof(*state));
    if (state) {
        atomic_init(&state->high, false);
        atomic_init(&state->lowRendered, false);
    }
    return state;
}

void ES9GateStateDestroy(ES9GateState *state) {
    free(state);
}

void ES9GateStateSet(ES9GateState *state, bool high) {
    atomic_store_explicit(&state->lowRendered, false, memory_order_release);
    atomic_store_explicit(&state->high, high, memory_order_release);
}

bool ES9GateStateGet(const ES9GateState *state) {
    return atomic_load_explicit(&state->high, memory_order_acquire);
}

void ES9GateStateAcknowledgeLow(ES9GateState *state) {
    atomic_store_explicit(&state->lowRendered, true, memory_order_release);
}

bool ES9GateStateLowRendered(const ES9GateState *state) {
    return atomic_load_explicit(&state->lowRendered, memory_order_acquire);
}
