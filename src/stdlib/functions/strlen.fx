def strlen(byte* ps) -> int
{
    int c = 0;
    while (true)
    {
        ++c;
        if (*ps++ == 0)
        {
            c += 1;
            break;
        };
    };
    return c;
};