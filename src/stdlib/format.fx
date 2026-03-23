// Author: Karac V. Thweatt

// redformat.fx - Text Formatting and Color Printing Library
// Provides ANSI color codes, text formatting, borders, and separators

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_FORMAT
#def FLUX_STANDARD_FORMAT 1;

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

namespace standard
{
    namespace format
    {
        // ============ ANSI COLOR CODES ============
        namespace colors
        {
            // Reset
            global const byte[] RESET = "\x1b[0m\0",
            
            // Regular colors
                                BLACK = "\x1b[30m\0",
                                RED = "\x1b[31m\0",
                                GREEN = "\x1b[32m\0",
                                YELLOW = "\x1b[33m\0",
                                BLUE = "\x1b[34m\0",
                                MAGENTA = "\x1b[35m\0",
                                CYAN = "\x1b[36m\0",
                                WHITE = "\x1b[37m\0",
            
            // Bright/Bold colors
                                BRIGHT_BLACK = "\x1b[90m\0",
                                BRIGHT_RED = "\x1b[91m\0",
                                BRIGHT_GREEN = "\x1b[92m\0",
                                BRIGHT_YELLOW = "\x1b[93m\0",
                                BRIGHT_BLUE = "\x1b[94m\0",
                                BRIGHT_MAGENTA = "\x1b[95m\0",
                                BRIGHT_CYAN = "\x1b[96m\0",
                                BRIGHT_WHITE = "\x1b[97m\0",
            
            // Background colors
                                BG_BLACK = "\x1b[40m\0",
                                BG_RED = "\x1b[41m\0",
                                BG_GREEN = "\x1b[42m\0",
                                BG_YELLOW = "\x1b[43m\0",
                                BG_BLUE = "\x1b[44m\0",
                                BG_MAGENTA = "\x1b[45m\0",
                                BG_CYAN = "\x1b[46m\0",
                                BG_WHITE = "\x1b[47m\0",
            
            // Bright background colors
                                BG_BRIGHT_BLACK = "\x1b[100m\0",
                                BG_BRIGHT_RED = "\x1b[101m\0",
                                BG_BRIGHT_GREEN = "\x1b[102m\0",
                                BG_BRIGHT_YELLOW = "\x1b[103m\0",
                                BG_BRIGHT_BLUE = "\x1b[104m\0",
                                BG_BRIGHT_MAGENTA = "\x1b[105m\0",
                                BG_BRIGHT_CYAN = "\x1b[106m\0",
                                BG_BRIGHT_WHITE = "\x1b[107m\0";
        };
        
        // ============ TEXT STYLES ============
        namespace styles
        {
            global const byte[] BOLD = "\x1b[1m\0",
                                DIM = "\x1b[2m\0",
                                ITALIC = "\x1b[3m\0",
                                UNDERLINE = "\x1b[4m\0",
                                BLINK = "\x1b[5m\0",
                                REVERSE = "\x1b[7m\0",
                                HIDDEN = "\x1b[8m\0",
                                STRIKETHROUGH = "\x1b[9m\0";
        };
        
        // ============ UTILITY FUNCTIONS ============
        
        // Print a character N times
        def print_charn(char c, int count) -> void
        {
            byte[2] char_str;
            char_str[0] = (byte)c;
            char_str[1] = (byte)0;
            
            for (int i = 0; i < count; i++)
            {
                print(char_str);
            };
        };
        
        // Print a string N times
        def print_repeat(byte* str, int count) -> void
        {
            for (int i = 0; i < count; i++)
            {
                print(str);
            };
        };
        
        // Print a horizontal line separator
        def print_separator(char c, int width) -> void
        {
            print_charn(c, width);
            print("\n\0");
        };
        
        // Print a horizontal line with specific character
        def hline(int width) -> void
        {
            print_separator('-', width);
        };
        
        def hline_heavy(int width) -> void
        {
            print_separator('=', width);
        };
        
        def hline_light(int width) -> void
        {
            print_separator('.', width);
        };
        
        // ============ COLORED PRINTING ============
        
        // Print text in color and reset
        def print_colored(byte* text, byte* color) -> void
        {
            print(color);
            print(text);
            print(colors::RESET);
        };
        
        // Print text in color with newline
        def println_colored(byte* text, byte* color) -> void
        {
            print(color);
            print(text);
            print(colors::RESET);
            print("\n\0");
        };
        
        // Convenience functions for common colors
        def print_red(byte* text) -> void
        {
            print_colored(text, colors::RED);
        };
        
        def print_green(byte* text) -> void
        {
            print_colored(text, colors::GREEN);
        };
        
        def print_blue(byte* text) -> void
        {
            print_colored(text, colors::BLUE);
        };
        
        def print_yellow(byte* text) -> void
        {
            print_colored(text, colors::YELLOW);
        };
        
        def print_cyan(byte* text) -> void
        {
            print_colored(text, colors::CYAN);
        };
        
        def print_magenta(byte* text) -> void
        {
            print_colored(text, colors::MAGENTA);
        };
        
        // ============ STYLED PRINTING ============
        
        // Print with style (bold, italic, etc)
        def print_styled(byte* text, byte* style) -> void
        {
            print(style);
            print(text);
            print(colors::RESET);
        };
        
        def print_bold(byte* text) -> void
        {
            print_styled(text, styles::BOLD);
        };
        
        def print_italic(byte* text) -> void
        {
            print_styled(text, styles::ITALIC);
        };
        
        def print_underline(byte* text) -> void
        {
            print_styled(text, styles::UNDERLINE);
        };
        
        // ============ BOX DRAWING ============
        
        // Box drawing characters
        namespace box
        {
            // Single line box characters
            global const char SINGLE_HORIZONTAL = '-';
            global const char SINGLE_VERTICAL = '|';
            global const char SINGLE_TOP_LEFT = '+';
            global const char SINGLE_TOP_RIGHT = '+';
            global const char SINGLE_BOTTOM_LEFT = '+';
            global const char SINGLE_BOTTOM_RIGHT = '+';
            global const char SINGLE_T_DOWN = '+';
            global const char SINGLE_T_UP = '+';
            global const char SINGLE_T_LEFT = '+';
            global const char SINGLE_T_RIGHT = '+';
            
            // Double line box characters (using ASCII alternatives)
            global const char DOUBLE_HORIZONTAL = '=';
            global const char DOUBLE_VERTICAL = '|';
            global const char DOUBLE_TOP_LEFT = '+';
            global const char DOUBLE_TOP_RIGHT = '+';
            global const char DOUBLE_BOTTOM_LEFT = '+';
            global const char DOUBLE_BOTTOM_RIGHT = '+';
        };
        
        // Print a box border top
        def print_box_top(int width, bool double_line) -> void
        {
            char h = double_line ? box::DOUBLE_HORIZONTAL : box::SINGLE_HORIZONTAL;
            char tl = double_line ? box::DOUBLE_TOP_LEFT : box::SINGLE_TOP_LEFT;
            char tr = double_line ? box::DOUBLE_TOP_RIGHT : box::SINGLE_TOP_RIGHT;
            
            print_charn(tl, 1);
            print_charn(h, width - 2);
            print_charn(tr, 1);
            print("\n\0");
        };
        
        // Print a box border bottom
        def print_box_bottom(int width, bool double_line) -> void
        {
            char h = double_line ? box::DOUBLE_HORIZONTAL : box::SINGLE_HORIZONTAL;
            char bl = double_line ? box::DOUBLE_BOTTOM_LEFT : box::SINGLE_BOTTOM_LEFT;
            char br = double_line ? box::DOUBLE_BOTTOM_RIGHT : box::SINGLE_BOTTOM_RIGHT;
            
            print_charn(bl, 1);
            print_charn(h, width - 2);
            print_charn(br, 1);
            print("\n\0");
        };
        
        // Print a box border side with text (left-aligned)
        def print_box_line(byte* text, int width, bool double_line) -> void
        {
            char v = double_line ? box::DOUBLE_VERTICAL : box::SINGLE_VERTICAL;
            
            // Calculate text length
            int text_len = 0;
            while (text[text_len] != (byte)0)
            {
                text_len++;
            };
            
            // Print left border
            print_charn(v, 1);
            print(" \0");
            
            // Print text
            print(text);
            
            // Calculate padding needed
            int padding = width - text_len - 4;
            if (padding > 0)
            {
                print_charn(' ', padding);
            };
            
            // Print right border
            print(" \0");
            print_charn(v, 1);
            print("\n\0");
        };
        
        // Print centered text in box
        def print_box_line_centered(byte* text, int width, bool double_line) -> void
        {
            char v = double_line ? box::DOUBLE_VERTICAL : box::SINGLE_VERTICAL;
            
            // Calculate text length
            int text_len = 0;
            while (text[text_len] != (byte)0)
            {
                text_len++;
            };
            
            // Calculate padding
            int total_padding = width - text_len - 4;
            int left_padding = total_padding / 2;
            int right_padding = total_padding - left_padding;
            
            // Print left border
            print_charn(v, 1);
            print(" \0");
            
            // Print left padding
            if (left_padding > 0)
            {
                print_charn(' ', left_padding);
            };
            
            // Print text
            print(text);
            
            // Print right padding
            if (right_padding > 0)
            {
                print_charn(' ', right_padding);
            };
            
            // Print right border
            print(" \0");
            print_charn(v, 1);
            print("\n\0");
        };
        
        // Print an empty box line
        def print_box_line_empty(int width, bool double_line) -> void
        {
            char v = double_line ? box::DOUBLE_VERTICAL : box::SINGLE_VERTICAL;
            
            print_charn(v, 1);
            print_charn(' ', width - 2);
            print_charn(v, 1);
            print("\n\0");
        };
        
        // ============ COMPLETE BOX DRAWING ============
        
        // Print a complete box with title
        def print_box(byte* title, int width, bool double_line) -> void
        {
            print_box_top(width, double_line);
            print_box_line_centered(title, width, double_line);
            print_box_bottom(width, double_line);
        };
        
        // Print a complete box with title and content
        def print_box_with_content(byte* title, byte* content, int width, bool double_line) -> void
        {
            print_box_top(width, double_line);
            print_box_line_centered(title, width, double_line);
            print_box_line_empty(width, double_line);
            print_box_line(content, width, double_line);
            print_box_bottom(width, double_line);
        };
        
        // ============ BANNER PRINTING ============
        
        // Print a simple banner
        def print_banner(byte* text, int width) -> void
        {
            hline_heavy(width);
            
            // Calculate text length
            int text_len = 0;
            while (text[text_len] != (byte)0)
            {
                text_len++;
            };
            
            // Calculate padding
            int total_padding = width - text_len;
            int left_padding = total_padding / 2;
            
            // Print centered text
            if (left_padding > 0)
            {
                print_charn(' ', left_padding);
            };
            print(text);
            print("\n\0");
            
            hline_heavy(width);
        };
        
        // Print a colored banner
        def print_banner_colored(byte* text, int width, byte* color) -> void
        {
            print(color);
            hline_heavy(width);
            
            // Calculate text length
            int text_len = 0;
            while (text[text_len] != (byte)0)
            {
                text_len++;
            };
            
            // Calculate padding
            int total_padding = width - text_len;
            int left_padding = total_padding / 2;
            
            // Print centered text
            if (left_padding > 0)
            {
                print_charn(' ', left_padding);
            };
            print(text);
            print(colors::RESET);
            print("\n\0");
            
            print(color);
            hline_heavy(width);
            print(colors::RESET);
        };
        
        // ============ PROGRESS INDICATORS ============
        
        // Print a progress bar
        def print_progress_bar(int current, int total, int width) -> void
        {
            int filled = (current * width) / total;
            int empty = width - filled;
            
            print("[\0");
            print_charn('#', filled);
            print_charn('-', empty);
            print("] \0");
            
            // Print percentage
            int percent = (current * 100) / total;
            print(percent);
            print("%\0");
        };
        
        // ============ TABLE FORMATTING ============
        
        // Print table separator
        def print_table_separator(int col_width, int num_cols) -> void
        {
            for (int i = 0; i < num_cols; i++)
            {
                print_charn('+', 1);
                print_charn('-', col_width);
            };
            print("+\n\0");
        };
        
        // Print table cell
        def print_table_cell(byte* text, int col_width) -> void
        {
            // Calculate text length
            int text_len = 0;
            while (text[text_len] != (byte)0)
            {
                text_len++;
            };
            
            print("| \0");
            print(text);
            
            // Pad to column width
            int padding = col_width - text_len - 2;
            if (padding > 0)
            {
                print_charn(' ', padding);
            };
        };
        
        // ============ STATUS MESSAGES ============
        
        // Print success message
        def print_success(byte* message) -> void
        {
            print_green("[SUCCESS]\0");
            print(" \0");
            print(message);
            print("\n\0");
        };
        
        // Print error message
        def print_error(byte* message) -> void
        {
            print_red("[ERROR]\0");
            print(" \0");
            print(message);
            print("\n\0");
        };
        
        // Print warning message
        def print_warning(byte* message) -> void
        {
            print_yellow("[WARNING]\0");
            print(" \0");
            print(message);
            print("\n\0");
        };
        
        // Print info message
        def print_info(byte* message) -> void
        {
            print_cyan("[INFO]\0");
            print(" \0");
            print(message);
            print("\n\0");
        };
        
        // ============ PADDING & ALIGNMENT ============
        
        // Print text with left padding
        def print_padded_left(byte* text, int total_width) -> void
        {
            // Calculate text length
            int text_len = 0;
            while (text[text_len] != (byte)0)
            {
                text_len++;
            };
            
            int padding = total_width - text_len;
            if (padding > 0)
            {
                print_charn(' ', padding);
            };
            print(text);
        };
        
        // Print text with right padding
        def print_padded_right(byte* text, int total_width) -> void
        {
            // Calculate text length
            int text_len = 0;
            while (text[text_len] != (byte)0)
            {
                text_len++;
            };
            
            print(text);
            
            int padding = total_width - text_len;
            if (padding > 0)
            {
                print_charn(' ', padding);
            };
        };
        
        // Print text centered
        def print_centered(byte* text, int total_width) -> void
        {
            // Calculate text length
            int text_len = 0;
            while (text[text_len] != (byte)0)
            {
                text_len++;
            };
            
            int total_padding = total_width - text_len;
            int left_padding = total_padding / 2;
            
            if (left_padding > 0)
            {
                print_charn(' ', left_padding);
            };
            print(text);
            print("\n\0");
        };
    };
};

#endif;
