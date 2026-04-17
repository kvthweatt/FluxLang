// vaultd.fx - simple vault server with custom binary protocol, MAC validation, and admin backdoor
// This challenge belongs to the "Root This Box" CTF, and is designed to test skills in binary exploitation, 
// protocol analysis, and vulnerability discovery. 
// The server implements a custom binary protocol for managing a simple key-value vault, 
// with a focus on demonstrating common pitfalls in protocol design and implementation.
#import "standard.fx", "net_windows.fx";

using standard::io::console,
      standard::net,
      standard::sockets,
      standard::strings;

// Constants
#def VAULT_SLOTS    16;
#def SLOT_NAME_MAX  32;
#def SLOT_DATA_MAX  128;
#def CMD_READ       0x01;
#def CMD_WRITE      0x02;
#def CMD_LIST       0x03;
#def CMD_ADMIN      0xFF;   // elevated command - admin path
#def MAC_SECRET     0xDEADBEEF;

// Standard request packet - used for regular read/write/list commands, with MAC validation
//  Byte offset   Field        Type          Notes
//  0             cmd          byte          Command selector
//  1             length       byte          Length of payload  ← 8-bit, max 255
//  2–3           flags        u16           Reserved / option flags
//  4–7           mac          u32           Big-endian HMAC checksum
//  8–…           payload      byte[length]  Key name + data
//
struct VaultRequest
{
    byte cmd,
         length;     // max payload bytes expected
    u16  flags;
    u32  mac;        // checksum of (cmd | length | flags | payload)
};

// Admin request packet - separate path for elevated commands, with wider length field but no MAC validation
//  Byte offset   Field        Type          Notes
//  0             cmd          byte          Always 0xFF in this path
//  1–2           length       u16           BIG-ENDIAN 16-bit length  ← wider!
//  3             flags        byte          Collapsed to single byte
//  4–7           mac          u32           Same checksum position
//  8–…           payload      byte[length]  Admin command payload
//
struct AdminRequest
{
    byte cmd;
    u16  length;     // <- promoted to 16-bit big-endian
    byte flags;
    u32  mac;
};

// Vault slot structure - represents a single key-value pair in the vault
struct VaultSlot
{
    byte[32]  name;
    byte[128] value;
    byte      locked,    // 1 = root-only read
              occupied;
};

// Global vault store - stack allocated at process start
VaultSlot[16] g_vault;

socket* g_client;

// net_send_err() - send a length-prefixed error string to the current client
// Wire format: 1 byte tag (0x45 = 'E'), 1 byte length, then the string bytes (no null)
def net_send_err(byte* msg) -> void
{
    // Measure string length (up to the null terminator)
    byte len;
    while (msg[len] != '\0') { len++; };

    byte[258] pkt;
    pkt[0] = (byte)0x45;   // 'E' — error tag
    pkt[1] = len;
    memcpy(@pkt[2], msg, (u16)len);

    tcp_send_all(g_client.fd, @pkt[0], (int)(len + 2));
};

// net_send_ok() - send a length-prefixed OK string to the current client
// Wire format: 1 byte tag (0x4F = 'O'), 1 byte length, then the string bytes (no null)
def net_send_ok(byte* msg) -> void
{
    byte len;
    while (msg[len] != '\0') { len++; };

    byte[258] pkt;
    pkt[0] = (byte)0x4F;   // 'O' — ok tag
    pkt[1] = len;
    memcpy(@pkt[2], msg, (u16)len);

    tcp_send_all(g_client.fd, @pkt[0], (int)(len + 2));
};

// net_send_data() - send a raw data blob to the current client
// Wire format: 1 byte tag (0x44 = 'D'), 2 byte little-endian length, then buf bytes
def net_send_data(byte* buf, u16 data_len) -> void
{
    byte[131] pkt;
    pkt[0] = (byte)0x44;                       // 'D' - data tag
    pkt[1] = (byte)(data_len `& 0xFF);         // low byte of length
    pkt[2] = (byte)((data_len >> 8) `& 0xFF);  // high byte of length
    memcpy(@pkt[3], buf, data_len);

    tcp_send_all(g_client.fd, @pkt[0], (int)(data_len + 3));
};

// Mac computation - simple custom algorithm, not cryptographically secure
def compute_mac(byte cmd, byte length, u16 flags, byte* payload, u16 plen) -> u32
{
    u32 h = MAC_SECRET ^ ((u32)cmd  << 24);
    h `^^= ((u32)length << 16);
    h `^^= (u32)flags;
    for (u16 i; i < plen; i++)
    {
        h = ((h << 5) | (h >> 27)) `^^ (u32)payload[i];
    };
    return h;
};

// Mac validation - compares computed MAC against request field, with endian mismatch vulnerability
def validate_mac(VaultRequest* req, byte* payload, u16 plen) -> bool
{
    le32 computed = compute_mac(req.cmd, req.length, req.flags, payload, plen);
    // req.mac is u32 (big-endian) - compare against little-endian computed     VULN?
    if (req.mac == computed)  // implicit host-endian cast of big-endian field
    {
        return true;
    };

    return false;
};

// Handle admin commands - separate path with wider length field but no MAC validation
def handle_admin(byte* raw_buf, u16 buf_len) -> bool
{
    // Overlay the ADMIN struct on the same raw bytes
    AdminRequest req from raw_buf[buf_len];

    // Payload is 8 bytes into the packet (after AdminRequest header)
    byte* payload = raw_buf + 8;

    // Stack-allocated work buffer - fixed 128 bytes
    byte[128] work_buf;

    // Bounds check uses buf_len (outer recv limit, max ~512)          VULN?
    // but req.length is u16 - can express values up to 65535
    // and the copy below uses req.length, not buf_len
    if (req.length > buf_len) { return true; };  // only guards against > recv size

    memcpy(@work_buf[0], payload, req.length);   // <- copies req.length bytes

    byte* cmd_str = @work_buf[0];
    vault_exec(cmd_str);

    return false;
};

// Main request dispatcher - handles all incoming packets and routes to appropriate handlers
def handle_request(byte* raw_buf, u16 buf_len) -> u32
{
    VaultRequest req from raw_buf[buf_len];
    byte* payload   = raw_buf + 8;
    u16  plen       = (u16)req.length;

    if (buf_len < 8) { return 1; };   // too short for header

    // Branch on CMD - admin path skips standard MAC check
    if (req.cmd == CMD_ADMIN)
    {
        // Admin path: no MAC validation performed here                 VULN?
        return handle_admin(raw_buf, buf_len); // true/false -> 1/0 returned
    };

    // Standard path: validate MAC before processing
    if (!validate_mac(@req, payload, plen))
    {
        net_send_err("AUTH_FAIL\0");
        return 2;
    };

    if      (req.cmd == CMD_READ)   { return handle_read(payload, plen); }
    else if (req.cmd == CMD_WRITE)  { return handle_write(payload, plen); }
    else if (req.cmd == CMD_LIST)   { return handle_list(); }
    else                            { return 3; };
};

// Write handler - creates or updates vault slots
def handle_write(byte* payload, u16 plen) -> u32
{
    // payload layout: [1-byte name_len][name][data]
    byte name_len = (byte)payload[0];
    if (name_len >= SLOT_NAME_MAX) { return 1; };

    byte* name_ptr = payload + 1,
          data_ptr = payload + 1 + name_len;
    u16   data_len = plen - (u16)(name_len + 1);

    // Find empty slot or matching name
    for (byte i; i < VAULT_SLOTS; i++)
    {
        if (!g_vault[i].occupied | memcmp(@g_vault[i].name, name_ptr, name_len) == 0)
        {`
            if (g_vault[i].locked) { net_send_err("LOCKED\0"); return 3; };
            if (data_len > SLOT_DATA_MAX) { return 2; };
            memcpy(@g_vault[i].value[0], data_ptr, data_len);
            g_vault[i].occupied = 1;
            net_send_ok("WRITTEN\0");
            return 0;
        };
    };
    return 4;
};

// Read handler - looks up vault slot by name and returns value
def handle_read(byte* payload, u16 plen) -> u32
{
    for (byte i; i < VAULT_SLOTS; i++)
    {
        if (g_vault[i].occupied & memcmp(@g_vault[i].name, payload, plen) == 0)
        {
            if (g_vault[i].locked) { net_send_err("LOCKED\0"); return 2; };
            net_send_data(@g_vault[i].value[0], 128);
            return 0;
        };
    };
    net_send_err("NOT_FOUND\0");
    return 1;
};

// Entry point
def main() -> int
{
    // Pre-populate locked root vault slot
    memcpy(@g_vault[0].name[0],  "root\0", 5);
    memcpy(@g_vault[0].value[0], "/flag contents here\0", 20);
    g_vault[0].locked   = 1;
    g_vault[0].occupied = 1;

    // Bind and listen on TCP 9977
    // Initialize Winsock
    int init_result = init();
    if (init_result != 0)
    {
        print("Failed to initialize Winsock\n\0");
        return 1;
    };
    
    print("=== TCP Echo Client ===\n\0");
    print("Connecting to server at 127.0.0.1:8080...\n\0");
    
    // Create TCP socket
    socket client_socket(socket_type.TCP);
    g_client = @client_socket;
    client_socket.fd = tcp_socket();
    
    if (!client_socket.is_open())
    {
        print("Failed to create socket\n\0");
        cleanup();
        return 1;
    };

    // Connect to server
    if (!client_socket.connect("127.0.0.1\0", 8080))
    {
        print("Failed to connect to server\n\0");
        client_socket.close();
        cleanup();
        return 1;
    };
    
    print("Connected to server!\n\0");

    byte[512] recv_buf;
    int client;
    u16 nbytes;

    for (;;)
    {
        client = accept(sock);
        nbytes = (u16)recv(client, @recv_buf[0], 512);
        handle_request(@recv_buf[0], nbytes);
        close(client);
    };

    return 0;
};