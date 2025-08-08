// Tests various lexer edge cases

def main() -> int 
{
    // Very long string literal
    char* longString = "This is a very long string that tests whether the lexer can handle extremely long string literals without breaking or causing memory issues in the tokenization process. This string continues for quite a while to stress test the string handling capabilities of the Flux lexer implementation.";
    
    // Numbers at boundaries
    int maxInt = 2147483647;
    int minInt = -2147483648;
    float smallFloat = 0.000001;
    float largeFloat = 999999.999999;
    
    // Special characters in strings
    char* specialChars = "!@#$%^&*()_+-=[]{}|;':\",./<>?`~";
    
    // Escaped characters
    char* escapes = "Line1\nLine2\tTabbed\rCarriageReturn\\Backslash\"Quote";
    
    // Mixed operators
    int result = ((maxInt + minInt) * 2) / (maxInt - minInt);
    
    return result;
};
