#import "standard.fx", "detour.fx";

using standard::io::console;

// ============================================================================
// Demo
// ============================================================================

// The function we will hook
def compute(ulong x) -> ulong
{
    return x * (ulong)3;
};

// Global detour instance so the hook can reach call_original
Detour g_detour;

// The hook — intercepts compute(), logs, calls original, modifies result
def hook_compute(ulong x) -> ulong
{
    print("  [hook] intercepted compute(\0");
    print(x);
    print(")\n\0");

    ulong original_result = g_detour.call_original(x);

    print("  [hook] original returned \0");
    print(original_result);
    print(", adding 1\n\0");

    return original_result + (ulong)1;
};

def main() -> int
{
    print("=== Flux Detour Hook Demo ===\n\0");

    // --- Baseline: call compute() before any hook ---
    print("\n[pre-hook]\n\0");
    ulong r1 = compute((ulong)7);
    print("  compute(7) = \0");
    print(r1);
    print("\n\0");

    // --- Install the detour ---
    print("\n[installing detour]\n\0");
    bool ok = g_detour.install((ulong)@compute, (ulong)@hook_compute);
    if (!ok)
    {
        print("  install failed\n\0");
        return 1;
    };
    print("  installed\n\0");

    // --- Call through the hook ---
    print("\n[hooked call]\n\0");
    ulong r2 = compute((ulong)7);
    print("  compute(7) via hook = \0");
    print(r2);
    print("\n\0");

    // --- Second hooked call with different input ---
    print("\n[hooked call 2]\n\0");
    ulong r3 = compute((ulong)10);
    print("  compute(10) via hook = \0");
    print(r3);
    print("\n\0");

    // --- Remove the hook ---
    print("\n[uninstalling detour]\n\0");
    g_detour.uninstall();
    print("  uninstalled\n\0");

    // --- Confirm original is restored ---
    print("\n[post-uninstall]\n\0");
    ulong r4 = compute((ulong)7);
    print("  compute(7) = \0");
    print(r4);
    print("\n\0");

    print("\n=== Done ===\n\0");
    return 0;
};
