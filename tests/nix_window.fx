// Flux Wayland Window Demo
// 800x600 black background, title "Flux Window"

#import "standard.fx", "redwayland.fx";

using standard::strings,
      standard::system::wayland,
      standard::io::console;

def main() -> int
{
    noopstr title = "Flux Window\0";

    Window win;
    win.__init((byte*)@title, 800, 600);

    if (!win.running)
    {
        return 1;
    };

    while (win.running)
    {
        win.clear(0);
        win.present();
        win.running = win.process_messages();
    };

    win.__exit();

    return 0;
};
