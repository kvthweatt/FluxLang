// donut.fx - Spinning ASCII Donut
// Inspired by the classic donut.c by Andy Sloane
//
// Demonstrates:
//   - Math operations (sin, cos approximations)
//   - Framebuffer technique
//   - Console animation
//   - Timing with Sleep

#import "standard.fx";
#import "redconsole.fx";

using standard::io::console;

// Approximate sin and cos using Taylor series
def sin(float x) -> float
{
    // Normalize to 0-2PI
    while (x > 6.283185) { x = x - 6.283185; };
    while (x < 0.0) { x = x + 6.283185; };
    
    // Taylor series for sin
    float x2 = x * x;
    float x3 = x2 * x;
    float x5 = x3 * x2;
    float x7 = x5 * x2;
    
    return x - (x3 / 6.0) + (x5 / 120.0) - (x7 / 5040.0);
};

def cos(float x) -> float
{
    return sin(x + 1.5707963); // sin(x + PI/2)
};

def main() -> int
{
    Console con;
    con.__init();
    
    // Fix handle
    i64* handle_ptr = (i64*)@con;
    handle_ptr[0] = WIN_STDOUT_HANDLE;
    con.refresh_size();
    
    // Hide cursor and clear screen
    con.cursor_visible(false);
    con.clear_screen();
    
    // Get console dimensions
    i16 width = con.get_width();
    i16 height = con.get_height();
    
    // Framebuffer
    byte[1920] output;  // 80x24 max
    float[1920] zbuffer;
    
    // Donut parameters
    float A = 0.0, B = 0.0;
    float theta, phi;
    float sinA, cosA, sinB, cosB, L;
    float sinTheta, cosTheta, sinPhi, cosPhi;
    float circle_x, circle_y, inv_z,
          x3d, y3d, z3d;
    int x, y, o, idx;
    
    // Animation loop
    while (true)
    {
        // Clear framebuffer
        for (int i = 0; i < 1920; i = i + 1)
        {
            output[i] = (byte)' ';
            zbuffer[i] = 0.0;
        };
        
        // Calculate sin/cos for current rotation
        sinA = sin(A);
        cosA = cos(A);
        sinB = sin(B);
        cosB = cos(B);
        
        // Generate donut
        theta = 0.0;
        while (theta < 6.28318)
        {
            sinTheta = sin(theta);
            cosTheta = cos(theta);
            
            phi = 0.0;
            while (phi < 6.28318)
            {
                sinPhi = sin(phi);
                cosPhi = cos(phi);
                
                // 3D coordinates of torus point
                circle_x = 1.5 + cosTheta * 0.5;  // Circle radius 0.5
                circle_y = sinTheta * 0.5;
                
                // 3D rotation
                x3d = circle_x * (cosB * cosPhi + sinA * sinB * sinPhi) - circle_y * cosA * sinB;
                y3d = circle_x * (sinB * cosPhi - sinA * cosB * sinPhi) + circle_y * cosA * cosB;
                z3d = cosA * circle_x * sinPhi + circle_y * sinA + 2.0;  // +2 to move camera back
                
                // Perspective projection
                inv_z = 1.0 / z3d;
                x = (int)(width / 2 + (int)x3d * 30 * (int)inv_z);
                y = (int)(height / 2 - (int)y3d * 30 * (int)inv_z);
                
                // Calculate luminance
                L = cosPhi * cosTheta * sinB - cosA * cosTheta * sinPhi - 
                          sinA * sinTheta + cosB * (cosA * sinTheta - cosTheta * sinA * sinPhi);
                
                // Draw if in bounds and closer than previous
                if (x >= 0 & x < width & y >= 0 & y < height)
                {
                    idx = x + y * width;
                    if (inv_z > zbuffer[idx])
                    {
                        zbuffer[idx] = inv_z;
                        
                        // Luminance to character (.,-~:;=!*#$@)
                        if (L > 0.0)
                        {
                            int lum_idx = (int)(L * 8.0);
                            if (lum_idx < 0) { lum_idx = 0; };
                            if (lum_idx > 11) { lum_idx = 11; };
                            
                            byte[] lum_chars = ".,-~:;=!*#$@\0";
                            output[idx] = lum_chars[lum_idx];
                        }
                        else
                        {
                            output[idx] = (byte)'.';
                        };
                    };
                };
                
                phi = phi + 0.07;  // Step phi
            };
            theta = theta + 0.07;  // Step theta
        };
        
        // Draw framebuffer
        con.cursor_set((i16)0, (i16)0);
        for (y = 0; y < height; y = y + 1)
        {
            for (x = 0; x < width; x = x + 1)
            {
                byte[2] ch;
                ch[0] = output[x + y * width];
                ch[1] = (byte)0;
                con.write(@ch[0]);
            };
        };
        
        // Update rotation angles
        A = A + 0.04;
        B = B + 0.08;
        
        // Control speed
        Sleep(30);
        
        // Check for key press to exit
        // (Simplified - press Ctrl+C to exit)
    };
    
    // Clean up
    con.cursor_visible(true);
    con.clear_screen();
    con.cursor_set((i16)0, (i16)0);
    
    return 0;
};