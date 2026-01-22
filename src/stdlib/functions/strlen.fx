def strlen(byte* ps) -> int
{
    int c = 0;
    while (true)
    {
        byte ch = *ps;

        if (ch == 0)
        {
            break;
        };
        // Anonymous block to visually separate the increments.
        {
            c++;
            ps++;        // ONE increment, in one place
        };
    };
    return c - 4;        // Need to do this for some reason?
};