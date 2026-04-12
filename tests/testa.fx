#import "standard.fx";

using standard::io::console;

struct Header
{
    unsigned data{16} sig;
    unsigned data{32} filesize, reserved, dataoffset;
};

struct InfoHeader
{
    unsigned data{32} size, width, height;
    unsigned data{16} planes, bitsperpixel;
    unsigned data{32} compression, imagesize, xpixelsperm, ypixelsperm, colorsused, importantcolors;
};

struct PostData
{
    int test;
};

struct BMP : Header, InfoHeader : PostData;

def main() -> int
{
    BMP bitmap;

    bitmap.test = 5;

    return 0;
};