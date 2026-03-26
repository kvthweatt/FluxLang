// flux_demo.fx - Flux Language Demo Video
//
// Space = advance to next step.  Escape = quit.
//
// Build: fc flux_demo.fx -o flux_demo.exe

#import "standard.fx", "math.fx", "windows.fx", "timing.fx", "gltextanim.fx";

using standard::math,
      standard::system::windows,
      opengl::textanim;

def main() -> int
{
    Renderer r("Flux Demo\0", 1280, 720,
               "C:\\Windows\\Fonts\\consola.ttf\0", 24);

    View view(@r);

    // Build the initial code on screen
    float lh = (float)r.font.cell_h;

    AnimStr line0("def foo() -> void\0",      32.0, lh * 1.0, COLOR_KEYWORD,   @r);
    AnimStr line1("{\0",                      32.0, lh * 2.0, COLOR_PUNCT,     @r);
    AnimStr line2("    return 0;\0",          32.0, lh * 3.0, COLOR_DEFAULT,   @r);
    AnimStr line3("};\0",                     32.0, lh * 4.0, COLOR_PUNCT,     @r);

    view.add(@line0);
    view.add(@line1);
    view.add(@line2);
    view.add(@line3);

    // Show initial state, wait for space
    if (!view.step_hold()) { return 0; };

    // Replace -> with <~ (tail call convention)
    if (!view.step_replace(@line0, "->\0", "<~\0", ANIM_FADE)) { return 0; };

    // Insert calling convention keyword
    if (!view.step_insert(@line0, 0, "stdcall \0", ANIM_WIPE_LR)) { return 0; };

    // Replace return with escape
    if (!view.step_replace(@line2, "return\0", "escape\0", ANIM_TYPE)) { return 0; };

    // Hold final state
    view.step_hold();

    return 0;
};
