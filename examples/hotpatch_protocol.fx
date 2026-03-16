// hotpatch_protocol.fx
//
// Shared protocol definitions for the hotpatch server/client demo.
//
// Wire format (all fields little-endian):
//
//   struct PatchPacket
//   {
//       u32  magic;        // 0x48505458 "HPTX" — sanity check
//       u32  patch_size;   // number of bytes in the payload
//       u64  target_rva;   // RVA from client image base to patch site
//                          // (0 = use target_addr directly, for demo)
//       byte payload[];    // raw machine code bytes, patch_size long
//   };
//
// The client reads the header first (16 bytes), allocates a page,
// receives exactly patch_size bytes into it, then installs the detour.

#ifndef HOTPATCH_PROTOCOL
#def HOTPATCH_PROTOCOL 1;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

// Magic bytes: "HPTX"
const uint PATCH_MAGIC = 0x48505458,
// Response codes sent server -> client after delivery
           PATCH_ACK  = 0x00000001,   // patch received and applied
           PATCH_NACK = 0x000000FF;   // something went wrong

// Fixed header size: magic(4) + patch_size(4) + target_rva(8) = 16 bytes
const int PATCH_HEADER_SIZE = 16,

// Maximum payload we'll accept (1 page)
          PATCH_MAX_SIZE = 4096;

// Hotpatch server port
const u16 HOTPATCH_PORT = 9900;


struct PatchHeader
{
    u32 magic,
        patch_size;
    u64 target_rva;
};

#endif;
