#import "standard.fx";
using standard::io::console;

macro TRANSITION(src, dst, cond)
{
    (cond) ? dst : src
};

macro TICK(state, input)
{
    TRANSITION(state, state + 1, input > 0)
};

macro LOG_STATE(s)
{
    println(f"state = {int(s)}\0")
};

enum FSMState { IDLE, RUNNING, PAUSED, DONE };

def run_machine(int[4] inputs) -> void
{
    FSMState state = FSMState.IDLE;

    for (int i = 0; i < 4; i++)
    {
        state = TICK(state, inputs[i]);
        LOG_STATE(state);
    };
};

def main() -> int
{
    int[4] inputs = [1, 1, 0, 1];
    run_machine(inputs);
    return 0;
};