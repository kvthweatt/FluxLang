#ifndef FLUX_STANDARD_SORTING
#def FLUX_STANDARD_SORTING 1;

namespace standard
{
    namespace sorting
    {
        // Bubble sort
        def bubble_sort<T>(T[] arr) -> void
        {
            int n = arr.length;
            for (int i; i < n - 1; i++)
            {
                for (int j; j < n - i - 1; j++)
                {
                    if (arr[j] > arr[j + 1])
                    {
                        T tmp = arr[j];
                        arr[j] = arr[j + 1];
                        arr[j + 1] = tmp;
                    };
                };
            };
        };
        
        // Selection sort
        def selection_sort<T>(T[] arr) -> void
        {
            int n = arr.length;
            for (int i; i < n - 1; i++)
            {
                int min = i;
                for (int j = i + 1; j < n; j++)
                {
                    if (arr[j] < arr[min])
                    {
                        min = j;
                    };
                };
                if (min != i)
                {
                    T tmp = arr[i];
                    arr[i] = arr[min];
                    arr[min] = tmp;
                };
            };
        };
        
        // Insertion sort
        def insertion_sort<T>(T[] arr) -> void
        {
            int n = arr.length;
            for (int i = 1; i < n; i++)
            {
                T key = arr[i];
                int j = i - 1;
                while (j >= 0 & arr[j] > key)
                {
                    arr[j + 1] = arr[j];
                    j--;
                };
                arr[j + 1] = key;
            };
        };
        
        // Quick sort
        def quick_sort<T>(T[] arr) -> void
        {
            def partition(T[] a, int low, int high) -> int
            {
                T pivot = a[high];
                int i = low - 1;
                
                for (int j = low; j < high; j++)
                {
                    if (a[j] <= pivot)
                    {
                        i++;
                        T tmp = a[i];
                        a[i] = a[j];
                        a[j] = tmp;
                    };
                };
                
                T tmp = a[i + 1];
                a[i + 1] = a[high];
                a[high] = tmp;
                
                return i + 1;
            };
            
            def sort(T[] a, int low, int high) -> void
            {
                if (low < high)
                {
                    int pi = partition(a, low, high);
                    sort(a, low, pi - 1);
                    sort(a, pi + 1, high);
                };
            };
            
            sort(arr, 0, arr.length - 1);
        };
        
        // Auto-select based on size
        def sort<T>(T[] arr) -> void
        {
            if (arr.length < 50)
            {
                insertion_sort(arr);
            }
            else
            {
                quick_sort(arr);
            };
        };
    };
};

#endif;