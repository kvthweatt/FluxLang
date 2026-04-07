// editor_core.fx - Gap buffer, line index, font metrics for fide

// ============================================================================
// GAP BUFFER
// ============================================================================

#def GAP_INITIAL   4096;
#def GAP_GROW      4096;

struct GapBuf
{
    byte* buf;
    int   buf_size;
    int   gap_start;
    int   gap_end;
};

def gb_len(GapBuf* g) -> int
{
    return g.buf_size - (g.gap_end - g.gap_start);
};

def gb_phys(GapBuf* g, int idx) -> int
{
    if (idx < g.gap_start) { return idx; };
    return idx + (g.gap_end - g.gap_start);
};

def gb_get(GapBuf* g, int idx) -> byte
{
    return g.buf[gb_phys(g, idx)];
};

def gb_move_gap(GapBuf* g, int pos) -> void
{
    int gap_len, i, dst;
    gap_len = g.gap_end - g.gap_start;
    if (pos == g.gap_start) { return; };
    if (pos < g.gap_start)
    {
        i = g.gap_start - 1;
        while (i >= pos)
        {
            dst = g.gap_end - 1 - (g.gap_start - 1 - i);
            g.buf[dst] = g.buf[i];
            i--;
        };
        g.gap_end   = g.gap_end - (g.gap_start - pos);
        g.gap_start = pos;
    }
    else
    {
        i = g.gap_end;
        while (i < pos + gap_len)
        {
            g.buf[g.gap_start + (i - g.gap_end)] = g.buf[i];
            i++;
        };
        g.gap_start = pos;
        g.gap_end   = pos + gap_len;
    };
    return;
};

def gb_ensure_gap(GapBuf* g, int need) -> bool
{
    int   gap_len, new_size, old_gap_end;
    void* new_buf;
    gap_len = g.gap_end - g.gap_start;
    if (gap_len >= need) { return true; };
    new_size    = g.buf_size + GAP_GROW;
    new_buf     = (void*)frealloc(long(g.buf), (size_t)new_size);
    if (new_buf == STDLIB_GVP) { return false; };
    g.buf        = (byte*)new_buf;
    old_gap_end  = g.gap_end;
    memmove((void*)(g.buf + old_gap_end + GAP_GROW),
            (void*)(g.buf + old_gap_end),
            (size_t)(g.buf_size - old_gap_end));
    g.gap_end    = old_gap_end + GAP_GROW;
    g.buf_size   = new_size;
    return true;
};

def gb_insert(GapBuf* g, int pos, byte ch) -> bool
{
    if (!gb_ensure_gap(g, 1)) { return false; };
    gb_move_gap(g, pos);
    g.buf[g.gap_start] = ch;
    g.gap_start++;
    return true;
};

def gb_delete(GapBuf* g, int pos) -> void
{
    int len;
    len = gb_len(g);
    if (pos < 0 | pos >= len) { return; };
    gb_move_gap(g, pos);
    g.gap_end++;
    return;
};

def gb_init(GapBuf* g) -> bool
{
    g.buf = (byte*)fmalloc((size_t)GAP_INITIAL);
    if (g.buf == STDLIB_GVP) { return false; };
    g.buf_size  = GAP_INITIAL;
    g.gap_start = 0;
    g.gap_end   = GAP_INITIAL;
    return true;
};

def gb_free(GapBuf* g) -> void
{
    if (g.buf != STDLIB_GVP) { ffree(long(g.buf)); };
    g.buf      = (byte*)STDLIB_GVP;
    g.buf_size = 0;
    g.gap_start = 0;
    g.gap_end   = 0;
    return;
};

def gb_flatten(GapBuf* g, byte* out) -> void
{
    int len, i;
    len = gb_len(g);
    i   = 0;
    while (i < len)
    {
        out[i] = gb_get(g, i);
        i++;
    };
    out[len] = (byte)0;
    return;
};

// ============================================================================
// LINE INDEX
// ============================================================================

#def LINE_INITIAL 1024;

struct LineIndex
{
    int* starts;
    int  count;
    int  cap;
};

def li_init(LineIndex* li) -> bool
{
    li.starts = (int*)fmalloc((size_t)(LINE_INITIAL * (sizeof(int) / 8)));
    if (li.starts == STDLIB_GVP) { return false; };
    li.cap   = LINE_INITIAL;
    li.count = 0;
    return true;
};

def li_free(LineIndex* li) -> void
{
    if (li.starts != STDLIB_GVP) { ffree(long(li.starts)); };
    li.starts = (int*)STDLIB_GVP;
    li.count  = 0;
    li.cap    = 0;
    return;
};

def li_rebuild(LineIndex* li, GapBuf* g) -> bool
{
    int   len, i, new_cap;
    void* new_buf;
    byte  ch;

    len      = gb_len(g);
    li.count = 0;

    if (li.cap < 1)
    {
        new_buf = (void*)frealloc(long(li.starts), (size_t)(LINE_INITIAL * (sizeof(int) / 8)));
        if (new_buf == STDLIB_GVP) { return false; };
        li.starts = (int*)new_buf;
        li.cap    = LINE_INITIAL;
    };

    li.starts[0] = 0;
    li.count     = 1;

    i = 0;
    while (i < len)
    {
        ch = gb_get(g, i);
        if (ch == (byte)10)
        {
            if (li.count >= li.cap)
            {
                new_cap = li.cap * 2;
                new_buf = (void*)frealloc(long(li.starts), (size_t)(new_cap * (sizeof(int) / 8)));
                if (new_buf == STDLIB_GVP) { return false; };
                li.starts = (int*)new_buf;
                li.cap    = new_cap;
            };
            li.starts[li.count] = i + 1;
            li.count++;
        };
        i++;
    };
    return true;
};

// Binary search: which line does offset fall on?
def li_line_of(LineIndex* li, int offset) -> int
{
    int lo, hi, mid;
    lo = 0;
    hi = li.count - 1;
    while (lo < hi)
    {
        mid = (lo + hi + 1) / 2;
        if (li.starts[mid] <= offset)
        {
            lo = mid;
        }
        else
        {
            hi = mid - 1;
        };
    };
    return lo;
};

def li_col_of(LineIndex* li, int offset) -> int
{
    int ln;
    ln = li_line_of(li, offset);
    return offset - li.starts[ln];
};

// Length of line ln (not including the newline)
def li_line_len(LineIndex* li, GapBuf* g, int ln) -> int
{
    int line_start, line_end, total_len;
    total_len  = gb_len(g);
    line_start = li.starts[ln];
    if (ln + 1 < li.count)
    {
        line_end = li.starts[ln + 1] - 1;
    }
    else
    {
        line_end = total_len;
    };
    return line_end - line_start;
};
