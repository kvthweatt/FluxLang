def main() -> int {
    unsigned data{64} as i64;

    for (volatile i64 x = 0; x < 1000000000000; x++) {};
    
    return 0;
};