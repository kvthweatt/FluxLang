#import "redstandard.fx", "redmath.fx", "redformat.fx";

using standard::io::console;
using standard::format;
using standard::math;

def mandelbrot(float x0, float y0, int max_iter) -> int
{
    float x = 0.0,
          y = 0.0,
          xtemp;
    int iter = 0;
    
    while (x*x + y*y <= 4.0 & iter < max_iter)
    {
        xtemp = x*x - y*y + x0;
        y = 2.0*x*y + y0;
        x = xtemp;
        iter++;
    };
    
    return iter;
};

def main() -> int
{
    print_banner("Mandelbrot Set Viewer\0", 60);
    
    float x_min = -2.0,
          x_max = 1.0,
          y_min = -1.2,
          y_max = 1.2,
          x, y;
    int width = 80,
        height = 40,
        max_iter = 100,
        iter,
        c;
    
    byte[81] line;
    
    for (int row = 0; row < height; row++)
    {
        y = y_min + (y_max - y_min) * (float)row / (float)(height - 1);
        
        for (int col = 0; col < width; col++)
        {
            x = x_min + (x_max - x_min) * (float)col / (float)(width - 1);
            
            iter = mandelbrot(x, y, max_iter);
            
            if (iter == max_iter)
            {
                line[col] = (byte)'#';
            }
            else
            {
                c = (iter * 10) % 4;
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