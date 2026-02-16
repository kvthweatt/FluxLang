#import "redstandard.fx";
#import "redformat.fx";

using standard::format;
using standard::format::colors;
using standard::format::styles;

def main() -> int
{
    // ============ DEMO 1: Color Printing ============
    print("\n\0");
    print_banner_colored("COLOR PRINTING DEMO\0", 60, colors::BRIGHT_CYAN);
    print("\n\0");
    
    print("Regular Colors:\n\0");
    print_red("  Red text\n\0");
    print_green("  Green text\n\0");
    print_blue("  Blue text\n\0");
    print_yellow("  Yellow text\n\0");
    print_cyan("  Cyan text\n\0");
    print_magenta("  Magenta text\n\0");
    
    print("\n\0");
    
    // ============ DEMO 2: Text Styles ============
    print_banner("TEXT STYLES DEMO\0", 60);
    print("\n\0");
    
    print("  \0");
    print_bold("Bold text\n\0");
    
    print("  \0");
    print_italic("Italic text\n\0");
    
    print("  \0");
    print_underline("Underlined text\n\0");
    
    print("  \0");
    print_styled("Dim text\n\0", styles::DIM);
    
    print("\n\0");
    
    // ============ DEMO 3: Separators ============
    print_banner("SEPARATORS DEMO\0", 60);
    print("\n\0");
    
    print("Light separator:\n\0");
    hline_light(60);
    
    print("\nNormal separator:\n\0");
    hline(60);
    
    print("\nHeavy separator:\n\0");
    hline_heavy(60);
    
    print("\nCustom character separator:\n\0");
    print_separator('*', 60);
    
    print("\nRepeating pattern:\n\0");
    print_repeat("-=\0", 30);
    print("\n\n\0");
    
    // ============ DEMO 4: Boxes ============
    print_banner("BOX DRAWING DEMO\0", 60);
    print("\n\0");
    
    print("Simple box:\n\0");
    print_box("FLUX LANGUAGE\0", 40, false);
    
    print("\nDouble-line box:\n\0");
    print_box("IMPORTANT NOTICE\0", 40, true);
    
    print("\nBox with content:\n\0");
    print_box_with_content("System Status\0", "All systems operational\0", 40, false);
    
    print("\n\0");
    
    // ============ DEMO 5: Status Messages ============
    print_banner("STATUS MESSAGES DEMO\0", 60);
    print("\n\0");
    
    print_success("Operation completed successfully\0");
    print_error("Failed to connect to server\0");
    print_warning("Low disk space detected\0");
    print_info("System update available\0");
    
    print("\n\0");
    
    // ============ DEMO 6: Progress Bars ============
    print_banner("PROGRESS BAR DEMO\0", 60);
    print("\n\0");
    
    print("Loading: \0");
    print_progress_bar(0, 100, 40);
    print("\n\0");
    
    print("Loading: \0");
    print_progress_bar(25, 100, 40);
    print("\n\0");
    
    print("Loading: \0");
    print_progress_bar(50, 100, 40);
    print("\n\0");
    
    print("Loading: \0");
    print_progress_bar(75, 100, 40);
    print("\n\0");
    
    print("Loading: \0");
    print_progress_bar(100, 100, 40);
    print("\n\n\0");
    
    // ============ DEMO 7: Text Alignment ============
    print_banner("TEXT ALIGNMENT DEMO\0", 60);
    print("\n\0");
    
    print("Left-aligned (20 width):\n\0");
    print_padded_left("Right side\n\0", 20);
    
    print("\nRight-aligned (20 width):\n\0");
    print_padded_right("Left side\0", 20);
    print("\n\0");
    
    print("\nCentered (60 width):\n\0");
    print_centered("This text is centered\0", 60);
    
    print("\n\0");
    
    // ============ DEMO 8: Table ============
    print_banner("TABLE FORMATTING DEMO\0", 60);
    print("\n\0");
    
    print_table_separator(15, 3);
    print_table_cell("Name\0", 15);
    print_table_cell("Age\0", 15);
    print_table_cell("City\0", 15);
    print("|\n\0");
    print_table_separator(15, 3);
    print_table_cell("Alice\0", 15);
    print_table_cell("30\0", 15);
    print_table_cell("NYC\0", 15);
    print("|\n\0");
    print_table_cell("Bob\0", 15);
    print_table_cell("25\0", 15);
    print_table_cell("LA\0", 15);
    print("|\n\0");
    print_table_separator(15, 3);
    
    print("\n\0");
    
    // ============ DEMO 9: Combined Effects ============
    print_banner_colored("COMBINED EFFECTS DEMO\0", 60, colors::BRIGHT_MAGENTA);
    print("\n\0");
    
    print(colors::BRIGHT_GREEN);
    print(styles::BOLD);
    print_box("SUCCESS!\0", 40, true);
    print(colors::RESET);
    
    print("\n\0");
    
    print(colors::BRIGHT_YELLOW);
    print("  \0");
    print_charn('*', 50);
    print("\n\0");
    print(colors::RESET);
    
    print("\n\0");
    hline_heavy(60);
    print_centered("End of Demo\0", 60);
    hline_heavy(60);
    
    print("\n\0");
    
    return 0;
};
