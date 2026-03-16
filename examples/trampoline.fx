// trampoline.fx
//
// A bytecode trampoline in Flux.
//
// A trampoline is a small stub of machine code that:
//   1. Receives a call
//   2. Redirects execution to a target address stored at a known offset
//      inside itself at runtime
//   3. Returns as if the target returned directly to the original caller
//
// Layout of the trampoline stub (x86-64, Windows calling convention):
//
//   Offset  Bytes   Meaning
//   ------  -----   -------
//   0       48 B8   MOV RAX, imm64   (opcode + reg encoding)
//   2       ?? ?? ?? ?? ?? ?? ?? ??  <- 8-byte target address (patched at runtime)
//   10      FF E0   JMP RAX          (absolute indirect jump through rax)
//
// Total: 12 bytes.
//
// The caller calls trampoline(), trampoline patches the 8 bytes at offset 2
// with the address of the real target function, then JMPs there.
// The target runs and returns directly to whoever called the trampoline.
// The trampoline itself never executes a RET.
//
// This is exactly how IAT hooks, detour patching, and hot-patchable stubs
// work at the binary level — we're just building it from first principles
// in a high level language.

#import "standard.fx";

using standard::io::console;

// ============================================================================
// Win32 memory primitives — we need PAGE_EXECUTE_READWRITE so the stub
// bytes we write are actually executable.  VirtualAlloc with flProtect=0x40.
// ============================================================================

extern
{
    def !!
        VirtualAlloc(ulong, size_t, u32, u32)  -> ulong,
        VirtualFree(ulong, size_t, u32)        -> bool,
        VirtualProtect(ulong, size_t, u32, u32*) -> bool;
};

// ============================================================================
// The real target functions — these are what the trampoline will redirect to.
// ============================================================================

def target_a(ulong x) -> ulong
{
    print("  [target_a] got: \0");
    print(x);
    print("\n\0");
    return x * (ulong)2;
};

def target_b(ulong x) -> ulong
{
    print("  [target_b] got: \0");
    print(x);
    print("\n\0");
    return x + (ulong)100;
};

def target_c(ulong x) -> ulong
{
    print("  [target_c] got: \0");
    print(x);
    print("\n\0");
    return x * x;
};

// ============================================================================
// Trampoline stub template
//
// 12 bytes:
//   48 B8  [8 bytes addr]  FF E0
//
// We allocate this on an executable page, patch the address slot,
// then hand back a typed function pointer to it.
// ============================================================================

// Allocate one executable page and write the stub template into it.
// Returns the base address of the page as ulong.
def alloc_stub_page() -> ulong
{
    // MEM_COMMIT | MEM_RESERVE = 0x3000, PAGE_EXECUTE_READWRITE = 0x40
    ulong page = VirtualAlloc((ulong)0, (size_t)4096, (u32)0x3000, (u32)0x40);
    return page;
};

// Write the 12-byte trampoline template into `page`.
// The 8-byte address slot (offset 2..9) is left as zeros — patch_target fills it.
def write_stub(ulong page) -> void
{
    byte* p = (byte*)page;

    // MOV RAX, imm64
    p[0]  = (byte)0x48;   // REX.W
    p[1]  = (byte)0xB8;   // MOV RAX, imm64

    // 8-byte address placeholder
    p[2]  = (byte)0x00;
    p[3]  = (byte)0x00;
    p[4]  = (byte)0x00;
    p[5]  = (byte)0x00;
    p[6]  = (byte)0x00;
    p[7]  = (byte)0x00;
    p[8]  = (byte)0x00;
    p[9]  = (byte)0x00;

    // JMP RAX
    p[10] = (byte)0xFF;
    p[11] = (byte)0xE0;
};

// Patch the 8-byte address slot in the stub at `page` with `target_addr`.
// Windows x86-64 is little-endian, so we write low byte first.
def patch_target(ulong page, ulong target_addr) -> void
{
    byte* p = (byte*)page;

    p[2] = (byte)(target_addr & (ulong)0xFF);
    p[3] = (byte)((target_addr >> (ulong)8)  & (ulong)0xFF);
    p[4] = (byte)((target_addr >> (ulong)16) & (ulong)0xFF);
    p[5] = (byte)((target_addr >> (ulong)24) & (ulong)0xFF);
    p[6] = (byte)((target_addr >> (ulong)32) & (ulong)0xFF);
    p[7] = (byte)((target_addr >> (ulong)40) & (ulong)0xFF);
    p[8] = (byte)((target_addr >> (ulong)48) & (ulong)0xFF);
    p[9] = (byte)((target_addr >> (ulong)56) & (ulong)0xFF);
};

// ============================================================================
// Main
// ============================================================================

def main() -> int
{
    print("=== Flux Bytecode Trampoline ===\n\0");

    // Allocate one executable page for our stub
    ulong stub_page = alloc_stub_page();

    // Write the MOV RAX / JMP RAX template once
    write_stub(stub_page);

    // The trampoline has signature (ulong) -> ulong — same as all three targets.
    // Cast the stub page to a typed function pointer.
    def{}* trampoline(ulong) -> ulong = (byte*)stub_page;

    // --- Round 1: redirect to target_a ---
    print("\n[trampoline -> target_a]\n\0");
    patch_target(stub_page, (ulong)@target_a);
    ulong r1 = trampoline((ulong)7);
    print("  result: \0");
    print(r1);
    print("\n\0");

    // --- Round 2: redirect to target_b ---
    print("\n[trampoline -> target_b]\n\0");
    patch_target(stub_page, (ulong)@target_b);
    ulong r2 = trampoline((ulong)7);
    print("  result: \0");
    print(r2);
    print("\n\0");

    // --- Round 3: redirect to target_c ---
    print("\n[trampoline -> target_c]\n\0");
    patch_target(stub_page, (ulong)@target_c);
    ulong r3 = trampoline((ulong)7);
    print("  result: \0");
    print(r3);
    print("\n\0");

    print("\n=== Done ===\n\0");

    VirtualFree(stub_page, (size_t)0, (u32)0x8000);
    return 0;
};
