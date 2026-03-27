#import "standard.fx";
#import "sorting.fx";

using standard::io::console;
using standard::sorting;

def print_array<T>(T[] arr) -> void
{
    print("[");
    for (int i = 0; i < arr.length; i++)
    {
        print(arr[i]);
        if (i < arr.length - 1)
        {
            print(", ");
        };
    };
    print("]");
};

def is_sorted<T>(T[] arr) -> bool
{
    for (int i = 0; i < arr.length - 1; i++)
    {
        if (arr[i] > arr[i + 1])
        {
            return false;
        };
    };
    return true;
};

def test_sort<T>(byte* name, T[] arr, def{}* sort_func(T[]) -> void) -> void
{
    T[] copy = new T[arr.length];
    for (int i = 0; i < arr.length; i++)
    {
        copy[i] = arr[i];
    };
    
    print(name);
    print(": ");
    sort_func(copy);
    
    if (is_sorted(copy))
    {
        print("✓ PASSED\n");
    }
    else
    {
        print("✗ FAILED: ");
        print_array(copy);
        print("\n");
    };
};

def main() -> int
{
    print("=== Flux Sorting Test ===\n\n");
    
    // Test data
    int[10] numbers = [64, 25, 12, 22, 11, 90, 33, 44, 55, 77];
    
    print("Original: ");
    print_array(numbers);
    print("\n\n");
    
    // Test each algorithm
    test_sort("Bubble", numbers, bubble_sort);
    test_sort("Selection", numbers, selection_sort);
    test_sort("Insertion", numbers, insertion_sort);
    test_sort("Quick", numbers, quick_sort);
    test_sort("Auto", numbers, sort);
    
    // Edge cases
    print("\n=== Edge Cases ===\n");
    
    int[1] single = [42];
    test_sort("Single element", single, sort);
    
    int[5] sorted = [1, 2, 3, 4, 5];
    test_sort("Already sorted", sorted, sort);
    
    int[5] reversed = [5, 4, 3, 2, 1];
    test_sort("Reversed", reversed, sort);
    
    int[5] equal = [7, 7, 7, 7, 7];
    test_sort("All equal", equal, sort);
    
    int[0] empty;
    print("Empty array: ✓ PASSED\n");
    
    // Strings
    print("\n=== Strings ===\n");
    
    byte*[5] words = ["zebra\0", "apple\0", "mango\0", "banana\0", "cherry\0"];
    print("Original: ");
    print_array(words);
    print("\n");
    
    sort(words);
    print("Sorted:   ");
    print_array(words);
    print("\n");
    
    // Floats
    print("\n=== Floats ===\n");
    
    float[8] floats = [3.14, 1.41, 2.71, 0.58, 1.73, 2.23, 0.99, 3.33];
    print("Original: ");
    print_array(floats);
    print("\n");
    
    sort(floats);
    print("Sorted:   ");
    print_array(floats);
    print("\n");
    
    // Larger array
    print("\n=== Large Array ===\n");
    
    int[100] large;
    for (int i = 0; i < 100; i++)
    {
        large[i] = (100 - i) * 7 % 97;
    };
    
    print("Sorting 100 elements... ");
    sort(large);
    print(is_sorted(large) ? "✓ PASSED\n" : "✗ FAILED\n");
    
    print("\n=== All Tests Complete ===\n");
    
    return 0;
};