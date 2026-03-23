// Author: Karac V. Thweatt

// fhf.fx
//
// Flux Hotpatch Framework (FHF) — Umbrella Header
//
// Import this single file to get the complete framework:
//
//   #import "fhf.fx";
//
// Module dependency order (each file guards against double-inclusion):
//
//   fhf_types.fx      — error codes, structs, constants
//   fhf_crypto.fx     — HMAC-SHA256 signing and verification
//   fhf_sym.fx        — symbol resolution (RVA / name / pattern / absaddr)
//   fhf_tramp.fx      — trampoline pool management
//   fhf_threads.fx    — thread suspension layer
//   fhf_engine.fx     — atomic patch apply and rollback
//   fhf_runtime.fx    — top-level manager (init / apply_bundle / rollback_all)
//   fhf_bundle.fx     — programmatic bundle construction
//   fhf_remote.fx     — TCP remote patch delivery (server + client)
//
// fhf_cli.fx is NOT included here because it defines main().
// Compile fhf_cli.fx separately as the fluxpatch executable.
//
// Minimum required imports before this file:
//   #import "standard.fx";      — for io::console (print)
//   #import "redcrypto.fx";     — for SHA256
//   #import "threading.fx";     — for spinlocks (spin_lock / spin_unlock)
//   #import "atomics.fx";       — for load32 / store32 / inc32 / dec32
//   #import "redmemory.fx";     — for malloc / free / VirtualAlloc / etc.

#ifndef FHF
#def FHF 1;

#import "fhf\\fhf_types.fx";
#import "fhf\\fhf_crypto.fx";
#import "fhf\\fhf_sym.fx";
#import "fhf\\fhf_tramp.fx";
#import "fhf\\fhf_threads.fx";
#import "fhf\\fhf_engine.fx";
#import "fhf\\fhf_runtime.fx";
#import "fhf\\fhf_bundle.fx";
#import "fhf\\fhf_remote.fx";

#endif; // FHF
