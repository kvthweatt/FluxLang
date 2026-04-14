#import "standard.fx", "windows.fx";

using standard::io::console,
      standard::strings,
      standard::math,
      standard::system::windows;

#def MAX_PATH 256;

def main(int argc, byte* argv) -> int
{
    if (argc != 2)
    {
        println(f"Usage: {find_last_char((byte*)argv[0], '\\') + 1} <username>");
        return 0;
    };

    char    *username = argv[1];
    char[MAX_PATH] password;
    DWORD    key_byte;

    strcpy(password, "HTS");

    for (int i; i < strlen(username); i++)
    {
        key_byte = ((username[i] - key_byte) >> 0x01) & `!(username[i] << ((byte)(((DWORD*)(key_byte)) & 0xFF)));
        if (i%2 == 0)
        {
            strcat(password, "-");
        };
        password += (byte[1])key_byte;
    };
    print(f"Username: {username}\n");
    print(f"Password: {password}\n");

    return 0;
};