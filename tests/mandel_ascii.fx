#import "redstandard.fx";
#import "redmath.fx";
#import "redformat.fx";

using standard::format;
using standard::math;

def mandelbrot(float x0, float y0, int max_iter) -> int
{
    float x = 0.0;
    float y = 0.0;
    int iter = 0;
    
    while (x*x + y*y <= 4.0 & iter < max_iter)
    {
        float xtemp = x*x - y*y + x0;
        y = 2.0*x*y + y0;
        x = xtemp;
        iter++;
    };
    
    return iter;
};

def main() -> int
{
    print_banner("Mandelbrot Set Viewer\0", 60);
    
    float x_min = -2.0;
    float x_max = 1.0;
    float y_min = -1.2;
    float y_max = 1.2;
    int width = 80;
    int height = 40;
    int max_iter = 100;
    
    byte[81] line;
    
    for (int row = 0; row < height; row++)
    {
        float y = y_min + (y_max - y_min) * (float)row / (float)(height - 1);
        
        for (int col = 0; col < width; col++)
        {
            float x = x_min + (x_max - x_min) * (float)col / (float)(width - 1);
            
            int iter = mandelbrot(x, y, max_iter);
            
            if (iter == max_iter)
            {
                line[col] = (byte)'#';
            }
            else
            {
                int c = (iter * 10) % 4;
                if (c == 0)   { line[col] = (byte)'.'; }
                elif (c == 1) { line[col] = (byte)':'; }
                elif (c == 2) { line[col] = (byte)'+'; }
                else          { line[col] = (byte)'*'; };
            };
        };
        
        line[width] = (byte)0;
        print(line);
        print("\n\0");
    };
    
    print_success("Mandelbrot set rendered");
    return 0;
};