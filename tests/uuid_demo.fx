#import "standard.fx", "format.fx", "random.fx", "uuid.fx";

using standard::format,
      standard::format::colors,
      standard::io::console,
      standard::random,
      standard::uuid;

def main() -> int
{
    print("\n\0");
    print_banner_colored("UUID GENERATION DEMO\0", 70, colors::BRIGHT_CYAN);
    print("\n\0");
    
    // Initialize RNG
    PCG32 rng;
    pcg32_init(@rng);
    
    byte[37] uuid_str;
    UUID uuid, uuid1, uuid2, nil_uuid, quick_uuid,
         uuid_copy_dest;
    
    // ============ DEMO 1: UUID Version 4 (Random) ============
    print_banner("UUID VERSION 4 (RANDOM)\0", 70);
    print("\n\0");
    
    print("UUID v4 is the most common type - completely random.\n\0");
    print("Generated 10 UUID v4 instances:\n\n\0");
    
    for (int i = 0; i < 10; i++)
    {
        uuid_v4(@uuid, @rng);
        uuid_to_string(@uuid, uuid_str);
        
        print("  \0");
        print_cyan(uuid_str);
        print("\n\0");
    };
    
    print("\n\0");
    
    // ============ DEMO 2: UUID Version 7 (Time-ordered) ============
    print_banner("UUID VERSION 7 (TIME-ORDERED)\0", 70);
    print("\n\0");
    
    print("UUID v7 is sortable by creation time (newest standard).\n\0");
    print("Generated 10 UUID v7 instances:\n\n\0");
    
    for (int i = 0; i < 10; i++)
    {
        uuid_v7(@uuid, @rng);
        uuid_to_string(@uuid, uuid_str);
        
        print("  \0");
        print_green(uuid_str);
        print("\n\0");
    };
    
    print("\n\0");
    
    // ============ DEMO 3: UUID Version 1 (Time-based) ============
    print_banner("UUID VERSION 1 (TIME-BASED)\0", 70);
    print("\n\0");
    
    print("UUID v1 is classic time-based (includes timestamp + node ID).\n\0");
    print("Generated 10 UUID v1 instances:\n\n\0");
    
    for (int i = 0; i < 10; i++)
    {
        uuid_v1(@uuid, @rng);
        uuid_to_string(@uuid, uuid_str);
        
        print("  \0");
        print_yellow(uuid_str);
        print("\n\0");
    };
    
    print("\n\0");
    
    // ============ DEMO 4: Different Formats ============
    print_banner("UUID FORMATTING OPTIONS\0", 70);
    print("\n\0");
    
    uuid_v4(@uuid, @rng);
    
    print("Same UUID in different formats:\n\n\0");
    
    print("  Lowercase: \0");
    uuid_to_string(@uuid, uuid_str);
    print(uuid_str);
    print("\n\0");
    
    print("  Uppercase: \0");
    uuid_to_string_upper(@uuid, uuid_str);
    print(uuid_str);
    print("\n\0");
    
    byte[33] hex_str;
    print("  Hex only:  \0");
    uuid_to_hex(@uuid, hex_str);
    print(hex_str);
    print("\n\0");
    
    print("\n\0");
    
    // ============ DEMO 5: UUID Operations ============
    print_banner("UUID OPERATIONS\0", 70);
    print("\n\0");
    
    uuid_v4(@uuid1, @rng);
    uuid_v4(@uuid2, @rng);
    
    uuid_to_string(@uuid1, uuid_str);
    print("UUID 1: \0");
    print(uuid_str);
    print("\n\0");
    
    uuid_to_string(@uuid2, uuid_str);
    print("UUID 2: \0");
    print(uuid_str);
    print("\n\0");
    
    if (uuid_equals(@uuid1, @uuid2))
    {
        print_success("UUIDs are equal\0");
    }
    else
    {
        print_info("UUIDs are different (expected)\0");
    };
    
    uuid_copy(@uuid_copy_dest, @uuid1);
    
    if (uuid_equals(@uuid1, @uuid_copy_dest))
    {
        print_success("UUID copy successful\0");
    };
    
    print("\nUUID 1 version: \0");
    print(uuid_version(@uuid1));
    print("\n\0");
    
    print("\n\0");
    
    // ============ DEMO 6: NIL UUID ============
    print_banner("NIL UUID\0", 70);
    print("\n\0");
    
    uuid_nil(@nil_uuid);
    
    uuid_to_string(@nil_uuid, uuid_str);
    print("NIL UUID: \0");
    print(uuid_str);
    print("\n\0");
    
    if (uuid_is_nil(@nil_uuid))
    {
        print_success("Correctly identified as NIL UUID\0");
    };
    
    print("\n\0");
    
    // ============ DEMO 7: Batch Generation ============
    print_banner("BATCH UUID GENERATION\0", 70);
    print("\n\0");
    
    UUID[5] batch_uuids;
    uuid_generate_batch_v4(batch_uuids, 5, @rng);
    
    print("Generated 5 UUIDs in a batch:\n\n\0");
    
    for (int i = 0; i < 5; i++)
    {
        uuid_to_string(@batch_uuids[i], uuid_str);
        print("  \0");
        print((int)(i + 1));
        print(". \0");
        print(uuid_str);
        print("\n\0");
    };
    
    print("\n\0");
    
    // ============ DEMO 8: Predefined Namespaces ============
    print_banner("PREDEFINED NAMESPACE UUIDS\0", 70);
    print("\n\0");
    
    print("RFC 4122 defines standard namespace UUIDs:\n\n\0");
    
    UUID ns_dns = UUID_NAMESPACE_DNS,
         ns_url = UUID_NAMESPACE_URL,
         ns_oid = UUID_NAMESPACE_OID,
         ns_x500 = UUID_NAMESPACE_X500;
    
    uuid_to_string(@ns_dns, uuid_str);
    print("  DNS:  \0");
    print(uuid_str);
    print("\n\0");
    
    uuid_to_string(@ns_url, uuid_str);
    print("  URL:  \0");
    print(uuid_str);
    print("\n\0");
    
    uuid_to_string(@ns_oid, uuid_str);
    print("  OID:  \0");
    print(uuid_str);
    print("\n\0");
    
    uuid_to_string(@ns_x500, uuid_str);
    print("  X500: \0");
    print(uuid_str);
    print("\n\n\0");
    
    // ============ DEMO 9: Quick Generation ============
    print_banner("QUICK UUID GENERATION\0", 70);
    print("\n\0");
    
    print("Using quick functions with global RNG:\n\n\0");

    print("Quick v4: \0");
    uuid_v4_quick(@quick_uuid);
    uuid_to_string(@quick_uuid, uuid_str);
    print(uuid_str);
    print("\n\0");
    
    print("Quick v7: \0");
    uuid_v7_quick(@quick_uuid);
    uuid_to_string(@quick_uuid, uuid_str);
    print(uuid_str);
    print("\n\0");
    
    print("Quick v1: \0");
    uuid_v1_quick(@quick_uuid);
    uuid_to_string(@quick_uuid, uuid_str);
    print(uuid_str);
    print("\n\n\0");
    
    // ============ DEMO 10: Use Cases ============
    print_banner("UUID USE CASES\0", 70);
    print("\n\0");
    
    print("Common UUID use cases:\n\n\0");
    
    print_info("Database primary keys\0");
    uuid_v7_quick(@uuid);
    uuid_to_string(@uuid, uuid_str);
    print("  ID: \0");
    print(uuid_str);
    print("\n\n\0");
    
    print_info("Session identifiers\0");
    uuid_v4_quick(@uuid);
    uuid_to_string(@uuid, uuid_str);
    print("  Session: \0");
    print(uuid_str);
    print("\n\n\0");
    
    print_info("Message/Transaction IDs\0");
    uuid_v4_quick(@uuid);
    uuid_to_string(@uuid, uuid_str);
    print("  TxID: \0");
    print(uuid_str);
    print("\n\n\0");
    
    print_info("File/Resource identifiers\0");
    uuid_v7_quick(@uuid);
    uuid_to_hex(@uuid, hex_str);
    print("  Resource: \0");
    print(hex_str);
    print("\n\n\0");
    
    // ============ END ============
    hline_heavy(70);
    print_centered("End of UUID Generation Demo\0", 70);
    hline_heavy(70);
    print("\n\0");
    
    return 0;
};
