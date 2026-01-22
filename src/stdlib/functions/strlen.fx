def strlen(byte* ps) -> int
{
    int c = 0;
    while (true)
    {
        byte* ch = ps++;

        if (*ch == 0)
        {
            break;
        };
        c++;
    };
    return c;
};