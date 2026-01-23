#import "redstandard.fx";

def main() -> int
{
    unsigned data{8} c = "C";
    unsigned data{1} as bit;
    bit* pb = @c; // 0 // First assignment works
    pb++;         // 1
    pb++;         // 0
    pb++;         // 0
    pb++;         // 0
    pb++;         // 0
    pb++;         // 1
    pb++;         // 1 <-- Should end at @c + 7
    pb = @c;      //   // Second assignment fails
    if (*pb == 1) { print("Correct.",8); };
    return 0;
};