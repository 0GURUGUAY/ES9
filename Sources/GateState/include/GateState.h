#ifndef ES9_GATE_STATE_H
#define ES9_GATE_STATE_H

#include <stdbool.h>

typedef struct ES9GateState ES9GateState;

ES9GateState *ES9GateStateCreate(void);
void ES9GateStateDestroy(ES9GateState *state);
void ES9GateStateSet(ES9GateState *state, bool high);
bool ES9GateStateGet(const ES9GateState *state);
void ES9GateStateAcknowledgeLow(ES9GateState *state);
bool ES9GateStateLowRendered(const ES9GateState *state);

#endif
