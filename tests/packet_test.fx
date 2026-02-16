#import "standard.fx";

struct Packet
{
    unsigned data{8} type;
    unsigned data{16} length;
    unsigned data{32} timestamp;
};

def main() -> int
{
    byte[7] bytes = [0x01, 0x00, 0x20, 0x5F, 0x12, 0x34, 0x56];
    Packet pkt from bytes;
    
    print("Type: \0");
    print(pkt.type); print();
    print("Length: \0");
    print(pkt.length); print();
    print("Time: \0");
    print(pkt.timestamp); print();
    
    return 0;
};