// File Analyzer
#import "standard.fx", "ffifio.fx";

def count_lines(byte* buffer, int size) -> int
{
    int line_count = 0;
    int i = 0;
    
    while (i < size)
    {
        if (buffer[i] == '\n')
        {
            line_count++;
        };
        i++;
    };
    
    if (size > 0 & buffer[size - 1] != '\n')
    {
        line_count++;
    };
    
    return line_count;
};

def count_words(byte* buffer, int size) -> int
{
    int word_count = 0;
    int in_word = 0;
    int i = 0;
    
    while (i < size)
    {
        byte c = buffer[i];
        
        if (c == ' ' | c == '\n' | c == '\t' | c == '\r')
        {
            if (in_word == 1)
            {
                word_count++;
                in_word = 0;
            };
        }
        else
        {
            in_word = 1;
        };
        
        i++;
    };
    
    if (in_word == 1)
    {
        word_count++;
    };
    
    return word_count;
};

def main() -> int
{
    noopstr filename = "build\\tmp.fx\0";
    
    print("=== File Analyzer ===\n\0");
    print("Analyzing file: \0");
    print(filename);
    print("\n\0");
    
    int file_size = get_file_size(filename);
    
    if (file_size <= 0)
    {
        print("Error: Could not read file or file is empty!\n\0");
        return 1;
    };
    
    byte* buffer = malloc((u64)file_size + 1);
    
    if (buffer == 0)
    {
        print("Error: Memory allocation failed!\n\0");
        return 1;
    };
    
    int bytes_read = read_file(filename, buffer, file_size);
    
    if (bytes_read <= 0)
    {
        print("Error: Failed to read file!\n\0");
        free(buffer);
        return 1;
    };
    
    buffer[bytes_read] = '\0';
    
    int lines = count_lines(buffer, bytes_read);
    int words = count_words(buffer, bytes_read);
    
    print("\nStatistics:\n\0");
    print("  Lines: \0");
    print(lines);
    print("\n  Words: \0");
    print(words);
    print("\n  Bytes: \0");
    print(bytes_read);
    print("\n\0");
    
    free(buffer);
    
    return 0;
};
