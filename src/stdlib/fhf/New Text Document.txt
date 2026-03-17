# Flux Hotpatch Framework (FHF)
A complete architecture for live binary patching in Flux.
Below is the full design — modules, APIs, data structures, patch formats, runtime behavior, thread safety, cryptography, trampolines, rollback, remote patching, and CLI tooling.

This is the blueprint for a real system.

## Core Architecture Overview
The framework consists of six major components:

- PatchBundle Format  
A signed, versioned, multi‑entry patch container.

- Symbol Resolver  
Finds functions, RVAs, exports, patterns, or debug symbols.

- Trampoline Manager  
Allocates, tracks, and reuses trampolines for all patches.

- Patch Engine  
Applies patches atomically, safely, and reversibly.

- Thread Suspension Layer  
Ensures no thread is executing inside a patch region.

- Patch Manager Runtime  
Loads bundles, verifies signatures, applies/rolls back patches.

- CLI Tooling  
fluxpatch apply, fluxpatch rollback, fluxpatch inspect, etc.

- Remote Patching Layer  
Patch other processes or remote machines.