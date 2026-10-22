#!/usr/bin/env python3
"""
vizcore.py -- Shared render core for Flux visualizers.

Provides two renderer classes:
  EffectGeomRenderer   -- effect algebra graph (used by eg.py)
  TypeGeomRenderer     -- type constraint graph  (used by tg.py)

Each renderer supports two modes:
  mini_frame(w, h, rot_x, rot_y, zoom) -> pygame.Surface
      Render a single frame into an offscreen surface. No display, no event
      loop. Safe to call from a Qt thread via pygame.display.init() with
      the null/offscreen driver.

  run_full(expr, title)
      Open an interactive pygame window and run the full event loop.
      Blocks until the window is closed.

Public API used by the IDE:
  render_effect_frame(expr, w, h) -> pygame.Surface
  render_type_frame(expr, w, h)   -> pygame.Surface
  launch_effect_full(expr)
  launch_type_full(expr)
"""

import pygame
import pygame.gfxdraw
import math
import colorsys
import sys
from dataclasses import dataclass, field
from typing import List, Optional, Set, Tuple, Dict

# ---------------------------------------------------------------------------
# Shared 3-D math
# ---------------------------------------------------------------------------

def sphere_layout(n: int) -> List[Tuple[float, float, float]]:
    pts = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(n):
        y = 1.0 - (i / max(n - 1, 1)) * 2.0
        r = math.sqrt(max(0.0, 1.0 - y * y))
        theta = golden * i
        x = math.cos(theta) * r
        z = math.sin(theta) * r
        pts.append((x * 2.0, y * 2.0, z * 2.0))
    return pts

def rotate_x(x, y, z, a):
    c, s = math.cos(a), math.sin(a)
    return x, y * c - z * s, y * s + z * c

def rotate_y(x, y, z, a):
    c, s = math.cos(a), math.sin(a)
    return x * c + z * s, y, -x * s + z * c

def project(x, y, z, fov, cx, cy):
    dz = z + 6.0
    if dz < 0.01:
        dz = 0.01
    return x * fov / dz + cx, -y * fov / dz + cy, dz

# ---------------------------------------------------------------------------
# Shared color helpers
# ---------------------------------------------------------------------------

def depth_fade_rgb(rgb, dz, bg=(18, 18, 20), min_dz=3.0, max_dz=12.0):
    t = max(0.0, min(1.0, (dz - min_dz) / (max_dz - min_dz)))
    a = 1.0 - t * 0.65
    return (
        int(rgb[0] * a + bg[0] * (1 - a)),
        int(rgb[1] * a + bg[1] * (1 - a)),
        int(rgb[2] * a + bg[2] * (1 - a)),
    )

def depth_scaled_size(base, dz, min_dz=3.0, max_dz=12.0):
    t = max(0.0, min(1.0, (dz - min_dz) / (max_dz - min_dz)))
    return max(7, int(round(base * (1.6 - t * 0.8))))

# ---------------------------------------------------------------------------
# Shared AA draw helpers
# ---------------------------------------------------------------------------

def draw_aa_line(surf, color, x1, y1, x2, y2, width=1, alpha=255):
    x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)
    if width <= 1:
        pygame.gfxdraw.aacircle(surf, x1, y1, 1, (*color, alpha))
        pygame.gfxdraw.line(surf, x1, y1, x2, y2, (*color, alpha))
        return
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy) or 1
    px, py = -dy / length, dx / length
    for w in range(-(width // 2), width // 2 + 1):
        ox, oy = int(px * w), int(py * w)
        pygame.gfxdraw.line(surf, x1+ox, y1+oy, x2+ox, y2+oy, (*color, alpha))

def draw_aa_circle(surf, color, cx, cy, r, alpha=255, fill=True, outline=True):
    cx, cy, r = int(cx), int(cy), int(r)
    if r < 1:
        return
    if fill:
        pygame.gfxdraw.filled_circle(surf, cx, cy, r, (*color, alpha))
    if outline:
        pygame.gfxdraw.aacircle(surf, cx, cy, r, (*color, min(255, alpha + 40)))

def _draw_arrowhead(surf, color, tip_x, tip_y, ux, uy, alpha, arrow_len=12, arrow_w=5):
    px, py = -uy * arrow_w, ux * arrow_w
    bx = tip_x - ux * arrow_len
    by = tip_y - uy * arrow_len
    pts = [
        (int(tip_x), int(tip_y)),
        (int(bx + px), int(by + py)),
        (int(bx - px), int(by - py)),
    ]
    pygame.gfxdraw.filled_trigon(surf, *pts[0], *pts[1], *pts[2], (*color, alpha))
    pygame.gfxdraw.aatrigon(surf,    *pts[0], *pts[1], *pts[2], (*color, alpha))

def draw_arrow_single(surf, color, x1, y1, x2, y2, width=2, alpha=255,
                      dash=False, directed=True):
    """Single-headed directed arrow from (x1,y1) to (x2,y2)."""
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy) or 1
    ux, uy = dx / length, dy / length
    arrow_len = 12
    ex, ey = x2 - ux * arrow_len, y2 - uy * arrow_len
    if dash:
        seg, gap = 10, 6
        ddx, ddy = ex - x1, ey - y1
        seg_len = math.hypot(ddx, ddy) or 1
        t = 0.0
        while t < 1.0:
            t0, t1 = t, min(t + seg / seg_len, 1.0)
            draw_aa_line(surf, color,
                         x1 + ddx * t0, y1 + ddy * t0,
                         x1 + ddx * t1, y1 + ddy * t1, width, alpha)
            t += (seg + gap) / seg_len
    else:
        draw_aa_line(surf, color, x1, y1, ex, ey, width, alpha)
    if directed:
        _draw_arrowhead(surf, color, x2, y2, ux, uy, alpha, arrow_len)

def draw_arrow_double(surf, color, x1, y1, x2, y2, width=2, alpha=255, dash=False):
    """Double-headed arrow (tg.py style)."""
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy) or 1
    ux, uy = dx / length, dy / length
    arrow_len = 12
    sx, sy = x1 + ux * arrow_len, y1 + uy * arrow_len
    ex, ey = x2 - ux * arrow_len, y2 - uy * arrow_len
    if dash:
        seg, gap = 10, 6
        ddx, ddy = ex - sx, ey - sy
        seg_len = math.hypot(ddx, ddy) or 1
        t = 0.0
        while t < 1.0:
            t0, t1 = t, min(t + seg / seg_len, 1.0)
            draw_aa_line(surf, color,
                         sx + ddx * t0, sy + ddy * t0,
                         sx + ddx * t1, sy + ddy * t1, width, alpha)
            t += (seg + gap) / seg_len
    else:
        draw_aa_line(surf, color, sx, sy, ex, ey, width, alpha)
    _draw_arrowhead(surf, color, x2, y2,  ux,  uy, alpha, arrow_len)
    _draw_arrowhead(surf, color, x1, y1, -ux, -uy, alpha, arrow_len)

def draw_aa_dashed_circle(surf, color, cx, cy, r, alpha=200, dash_deg=18):
    cx, cy, r = int(cx), int(cy), int(r)
    steps = 360 // dash_deg
    W, H = surf.get_width(), surf.get_height()
    for i in range(steps):
        if i % 2 == 0:
            continue
        a0 = math.radians(i * dash_deg)
        a1 = math.radians((i + 1) * dash_deg)
        for t in range(8):
            a = a0 + (a1 - a0) * (t / 7.0)
            x = int(cx + math.cos(a) * r)
            y = int(cy + math.sin(a) * r)
            if 0 <= x < W and 0 <= y < H:
                pygame.gfxdraw.pixel(surf, x, y, (*color, alpha))

# ---------------------------------------------------------------------------
# Shared font / text
# ---------------------------------------------------------------------------

_font_cache: Dict[tuple, pygame.font.Font] = {}

def get_font(size: int, bold: bool = False) -> pygame.font.Font:
    key = (size, bold)
    if key not in _font_cache:
        try:
            _font_cache[key] = pygame.font.SysFont('consolas,monospace', size, bold=bold)
        except Exception:
            _font_cache[key] = pygame.font.Font(None, size)
    return _font_cache[key]

def draw_text(surf, text, x, y, size=13, color=(220, 220, 220), bold=False,
              anchor='center', alpha=255):
    font = get_font(size, bold)
    rendered = font.render(text, True, color)
    if alpha < 255:
        rendered.set_alpha(alpha)
    rect = rendered.get_rect()
    if anchor == 'center':
        rect.center = (int(x), int(y))
    elif anchor == 'topleft':
        rect.topleft = (int(x), int(y))
    elif anchor == 'midleft':
        rect.midleft = (int(x), int(y))
    surf.blit(rendered, rect)
    return rect

# ---------------------------------------------------------------------------
# Shared camera / input state
# ---------------------------------------------------------------------------

@dataclass
class CameraState:
    rot_x:       float = 0.2
    rot_y:       float = 0.4
    zoom:        float = 1.0
    auto_rotate: bool  = True
    idle_timer:  int   = 0
    ease_t:      float = 1.0
    IDLE_DELAY:  int   = 5000

@dataclass
class TextInputState:
    text:       str  = ''
    cursor_pos: int  = 0
    sel_start:  int  = 0
    sel_end:    int  = 0
    active:     bool = False
    x_offset:   int  = 0
    sel_drag:   bool = False
    cur_vis:    bool = True
    cur_timer:  int  = 0

    def move_cursor(self, pos: int, extend: bool):
        self.cursor_pos = max(0, min(len(self.text), pos))
        if extend:
            self.sel_end = self.cursor_pos
        else:
            self.sel_start = self.sel_end = self.cursor_pos

    def sel_range(self):
        return min(self.sel_start, self.sel_end), max(self.sel_start, self.sel_end)

    def has_sel(self):
        return self.sel_start != self.sel_end

    def delete_sel(self):
        lo, hi = self.sel_range()
        self.text = self.text[:lo] + self.text[hi:]
        self.cursor_pos = self.sel_start = self.sel_end = lo

    def word_left(self):
        p = self.cursor_pos - 1
        while p > 0 and not self.text[p-1].isalnum(): p -= 1
        while p > 0 and self.text[p-1].isalnum():     p -= 1
        return p

    def word_right(self):
        p = self.cursor_pos
        while p < len(self.text) and not self.text[p].isalnum(): p += 1
        while p < len(self.text) and self.text[p].isalnum():     p += 1
        return p

    def scroll_to_cursor(self, clip_w: int, font):
        cx = font.size(self.text[:self.cursor_pos])[0]
        scx = cx + self.x_offset
        margin = 6
        if scx < margin:
            self.x_offset = -cx + margin
        elif scx > clip_w - margin:
            self.x_offset = clip_w - cx - margin

    def pos_from_x(self, px: int, font) -> int:
        best = len(self.text)
        for i in range(len(self.text) + 1):
            cx = font.size(self.text[:i])[0]
            if cx >= px:
                if i > 0 and abs(font.size(self.text[:i-1])[0] - px) < abs(cx - px):
                    return i - 1
                return i
        return best

# ---------------------------------------------------------------------------
# Shared top-bar / panel draw helpers
# ---------------------------------------------------------------------------

BG_COLOR   = (18, 18, 20)
PANEL_W    = 240
TOP_H      = 46
CANVAS_W   = 1100
CANVAS_H   = 720
NODE_RADIUS = 20
LANE_SPACING = 14

def draw_top_bar(screen, W, H, inp: TextInputState, auto_rotate: bool,
                 label='Effect expr:') -> Tuple[pygame.Rect, pygame.Rect, pygame.Rect]:
    """
    Draw the top bar with text input and Visualize button.
    Returns (input_rect, btn_rect, ar_rect).
    """
    bar_w = W - PANEL_W
    pygame.draw.rect(screen, (28, 28, 32), (0, 0, bar_w, TOP_H))
    pygame.draw.line(screen, (50, 50, 55), (0, TOP_H - 1), (bar_w, TOP_H - 1))

    draw_text(screen, label, 10, TOP_H // 2, size=12,
              color=(150, 150, 150), anchor='midleft')

    label_w = get_font(12).size(label)[0] + 16
    input_x = label_w
    input_w = bar_w - input_x - 120
    input_rect = pygame.Rect(input_x, 7, input_w, TOP_H - 14)
    clip_rect  = input_rect.inflate(-8, -4)

    box_col  = (45, 50, 60) if inp.active else (35, 35, 40)
    bord_col = (80, 130, 200) if inp.active else (55, 55, 60)
    pygame.draw.rect(screen, box_col,  input_rect, border_radius=4)
    pygame.draw.rect(screen, bord_col, input_rect, 1, border_radius=4)

    font = get_font(12)
    ty   = input_rect.y + (input_rect.h - font.get_height()) // 2
    inp.scroll_to_cursor(clip_rect.width, font)
    tx = clip_rect.x + inp.x_offset

    screen.set_clip(clip_rect)
    if inp.active and inp.has_sel():
        lo, hi = inp.sel_range()
        sx0 = tx + font.size(inp.text[:lo])[0]
        sx1 = tx + font.size(inp.text[:hi])[0]
        sel_r = pygame.Rect(sx0, ty, sx1 - sx0, font.get_height()).clip(clip_rect)
        pygame.draw.rect(screen, (60, 100, 180), sel_r)
    screen.blit(font.render(inp.text, True, (210, 220, 235)), (tx, ty))
    if inp.active and inp.cur_vis and not inp.has_sel():
        ncx = tx + font.size(inp.text[:inp.cursor_pos])[0]
        pygame.draw.line(screen, (200, 220, 255),
                         (int(ncx), ty + 1), (int(ncx), ty + font.get_height() - 1))
    screen.set_clip(None)

    btn_x    = bar_w - 115
    btn_rect = pygame.Rect(btn_x, 8, 105, TOP_H - 16)
    pygame.draw.rect(screen, (45, 80, 130), btn_rect, border_radius=4)
    pygame.draw.rect(screen, (70, 110, 180), btn_rect, 1, border_radius=4)
    draw_text(screen, 'Visualize', btn_rect.centerx, btn_rect.centery,
              size=12, bold=True, color=(200, 220, 255), anchor='center')

    ar_x   = btn_x - 120
    ar_lbl = 'Auto-rotate: ON' if auto_rotate else 'Auto-rotate: OFF'
    ar_col = (100, 200, 120) if auto_rotate else (160, 80, 80)
    ar_rect = draw_text(screen, ar_lbl, ar_x, TOP_H // 2,
                        size=11, color=ar_col, anchor='midleft')

    return input_rect, btn_rect, ar_rect

def draw_panel_bg(screen, W, H, legend_surf, info_surf):
    panel_x = W - PANEL_W
    pygame.draw.rect(screen, (22, 22, 22), (panel_x, TOP_H, PANEL_W, H - TOP_H))
    pygame.draw.line(screen, (45, 45, 50), (panel_x, TOP_H), (panel_x, H))
    screen.blit(legend_surf, (panel_x, TOP_H))
    screen.blit(info_surf, (panel_x, H - info_surf.get_height()))

def draw_status(screen, W, H, status: str):
    bar_w = W - PANEL_W
    draw_text(screen, status, bar_w // 2, H - 14,
              size=10, color=(80, 80, 80), anchor='center')

def draw_ring(screen, W, H):
    cw, ch = W - PANEL_W, H - TOP_H
    ring_r = int(min(cw, ch) * 0.42)
    pygame.gfxdraw.aacircle(screen, cw // 2, TOP_H + ch // 2, ring_r, (45, 45, 45, 120))

def handle_text_input_event(event, inp: TextInputState,
                             input_rect: Optional[pygame.Rect]) -> bool:
    """
    Handle keyboard/mouse events for the text input box.
    Returns True if event was consumed.
    """
    if event.type == pygame.KEYDOWN and inp.active:
        ctrl  = pygame.key.get_mods() & pygame.KMOD_CTRL
        shift = pygame.key.get_mods() & pygame.KMOD_SHIFT
        if ctrl and event.key == pygame.K_a:
            inp.sel_start = 0
            inp.sel_end = inp.cursor_pos = len(inp.text)
        elif ctrl and event.key == pygame.K_c:
            lo, hi = inp.sel_range()
            if lo < hi:
                try: pygame.scrap.put(pygame.SCRAP_TEXT, inp.text[lo:hi].encode())
                except Exception: pass
        elif ctrl and event.key == pygame.K_x:
            lo, hi = inp.sel_range()
            if lo < hi:
                try: pygame.scrap.put(pygame.SCRAP_TEXT, inp.text[lo:hi].encode())
                except Exception: pass
                inp.delete_sel()
        elif ctrl and event.key == pygame.K_v:
            try:
                data = pygame.scrap.get(pygame.SCRAP_TEXT)
                if data:
                    text = data.decode('utf-8', errors='ignore').rstrip(chr(0))
                    if inp.has_sel(): inp.delete_sel()
                    p = inp.cursor_pos
                    inp.text = inp.text[:p] + text + inp.text[p:]
                    inp.move_cursor(p + len(text), False)
            except Exception: pass
        elif event.key == pygame.K_BACKSPACE:
            if inp.has_sel(): inp.delete_sel()
            elif ctrl:
                np = inp.word_left()
                inp.text = inp.text[:np] + inp.text[inp.cursor_pos:]
                inp.move_cursor(np, False)
            elif inp.cursor_pos > 0:
                p = inp.cursor_pos
                inp.text = inp.text[:p-1] + inp.text[p:]
                inp.move_cursor(p - 1, False)
        elif event.key == pygame.K_DELETE:
            if inp.has_sel(): inp.delete_sel()
            elif ctrl:
                np = inp.word_right()
                inp.text = inp.text[:inp.cursor_pos] + inp.text[np:]
            else:
                p = inp.cursor_pos
                inp.text = inp.text[:p] + inp.text[p+1:]
        elif event.key == pygame.K_LEFT:
            if not shift and inp.has_sel():
                lo, _ = inp.sel_range(); inp.move_cursor(lo, False)
            elif ctrl: inp.move_cursor(inp.word_left(), shift)
            else:      inp.move_cursor(inp.cursor_pos - 1, shift)
        elif event.key == pygame.K_RIGHT:
            if not shift and inp.has_sel():
                _, hi = inp.sel_range(); inp.move_cursor(hi, False)
            elif ctrl: inp.move_cursor(inp.word_right(), shift)
            else:      inp.move_cursor(inp.cursor_pos + 1, shift)
        elif event.key == pygame.K_HOME: inp.move_cursor(0, shift)
        elif event.key == pygame.K_END:  inp.move_cursor(len(inp.text), shift)
        else:
            ch = event.unicode
            if ch and ch.isprintable():
                if inp.has_sel(): inp.delete_sel()
                p = inp.cursor_pos
                inp.text = inp.text[:p] + ch + inp.text[p:]
                inp.move_cursor(p + 1, False)
        return True

    if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
        if input_rect and input_rect.collidepoint(event.pos):
            inp.active = True
            inp.sel_drag = True
            font   = get_font(12)
            clip_x = input_rect.x + 4
            px     = event.pos[0] - clip_x - inp.x_offset
            pos    = inp.pos_from_x(px, font)
            shift  = pygame.key.get_mods() & pygame.KMOD_SHIFT
            if shift: inp.move_cursor(pos, True)
            else:
                inp.move_cursor(pos, False)
                inp.sel_start = pos
            return True

    if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
        inp.sel_drag = False

    if event.type == pygame.MOUSEMOTION and inp.sel_drag and inp.active and input_rect:
        font   = get_font(12)
        clip_x = input_rect.x + 4
        px     = event.pos[0] - clip_x - inp.x_offset
        pos    = inp.pos_from_x(px, font)
        inp.cursor_pos = pos
        inp.sel_end    = pos
        return True

    return False

# ---------------------------------------------------------------------------
# Node base class
# ---------------------------------------------------------------------------

@dataclass
class GraphNode:
    name: str
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    sx: float = 0.0
    sy: float = 0.0
    sz: float = 0.0

# ---------------------------------------------------------------------------
# Shared graph renderer base
# ---------------------------------------------------------------------------

class GraphRenderer:
    """
    Base class for EffectGeomRenderer and TypeGeomRenderer.
    Subclasses implement:
      _node_color(name) -> RGB tuple
      _draw_edges(surf, nodes, relations, W, H)
      _draw_node(surf, node, selected, W, H)
      _build_legend_surf() -> pygame.Surface
      _build_info_surf(node, relations) -> pygame.Surface
      _build_graph(expr) -> (nodes, relations, status_str)
    """

    BG = (18, 18, 20)

    def __init__(self):
        self.nodes:     List[GraphNode] = []
        self.relations: list            = []
        self.selected:  Optional[GraphNode] = None
        self.cam        = CameraState()
        self.status     = ''
        self.legend_surf: Optional[pygame.Surface] = None
        self.info_surf:   Optional[pygame.Surface] = None

    def load_expr(self, expr: str):
        nodes, relations, status = self._build_graph(expr)
        self.nodes     = nodes
        self.relations = relations
        self.status    = status
        self.selected  = None
        if self.legend_surf:
            self.info_surf = self._build_info_surf(None, [])

    def _project_nodes(self, W: int, H: int):
        cw, ch = W - PANEL_W, H - TOP_H
        cx, cy = cw / 2, TOP_H + ch / 2
        fov = 480 * self.cam.zoom
        for node in self.nodes:
            x, y, z = node.x, node.y, node.z
            x, y, z = rotate_x(x, y, z, self.cam.rot_x)
            x, y, z = rotate_y(x, y, z, self.cam.rot_y)
            sx, sy, dz = project(x, y, z, fov, cx, cy)
            node.sx, node.sy, node.sz = sx, sy, dz

    def render_frame(self, surf: pygame.Surface):
        """Render one frame into surf. Does not flip display."""
        W, H = surf.get_size()
        surf.fill(self.BG)
        draw_ring(surf, W, H)
        if self.nodes:
            self._project_nodes(W, H)
            self._draw_edges(surf, W, H)
            for node in sorted(self.nodes, key=lambda n: n.sz, reverse=True):
                self._draw_node(surf, node, W, H)
        if self.legend_surf:
            draw_panel_bg(surf, W, H, self.legend_surf, self.info_surf)
        draw_status(surf, W, H, self.status)

    def mini_frame(self, w: int, h: int) -> pygame.Surface:
        """
        Render a single frame into an offscreen surface of size (w, h).
        No panel / legend -- just the 3-D graph centered in the full surface.
        """
        surf = pygame.Surface((w, h))
        surf.fill(self.BG)
        if not self.nodes:
            return surf

        # Temporarily override geometry to fill mini frame
        cw, ch = w, h
        cx, cy = cw / 2, ch / 2
        fov = 300 * self.cam.zoom

        for node in self.nodes:
            x, y, z = node.x, node.y, node.z
            x, y, z = rotate_x(x, y, z, self.cam.rot_x)
            x, y, z = rotate_y(x, y, z, self.cam.rot_y)
            dz = z + 6.0
            if dz < 0.01: dz = 0.01
            node.sx = x * fov / dz + cx
            node.sy = -y * fov / dz + cy
            node.sz = dz

        self._draw_edges(surf, w, h)
        for node in sorted(self.nodes, key=lambda n: n.sz, reverse=True):
            self._draw_node(surf, node, w, h)

        return surf

    def node_by_name(self, name: str) -> Optional[GraphNode]:
        for n in self.nodes:
            if n.name == name:
                return n
        return None

    def node_at(self, mx: int, my: int, radius: float = 35.0) -> Optional[GraphNode]:
        best, best_d = None, radius
        for node in self.nodes:
            d = math.hypot(node.sx - mx, node.sy - my)
            if d < best_d:
                best_d, best = d, node
        return best

    # Subclasses must implement:
    def _build_graph(self, expr: str): raise NotImplementedError
    def _draw_edges(self, surf, W, H): raise NotImplementedError
    def _draw_node(self, surf, node, W, H): raise NotImplementedError
    def _build_legend_surf(self) -> pygame.Surface: raise NotImplementedError
    def _build_info_surf(self, node, relations) -> pygame.Surface: raise NotImplementedError

# ---------------------------------------------------------------------------
# Full interactive window runner (shared by both visualizers)
# ---------------------------------------------------------------------------

def run_interactive(renderer: GraphRenderer, title: str,
                    input_label: str, initial_expr: str):
    """
    Open a pygame window and run the interactive loop for the given renderer.
    Blocks until the window is closed.
    """
    pygame.init()
    try:
        pygame.scrap.init()
    except Exception:
        pass

    W, H = CANVAS_W, CANVAS_H
    screen = pygame.display.set_mode((W, H), pygame.RESIZABLE)
    pygame.display.set_caption(title)
    clock  = pygame.time.Clock()

    renderer.legend_surf = renderer._build_legend_surf()
    renderer.info_surf   = renderer._build_info_surf(None, [])
    renderer.load_expr(initial_expr)

    inp = TextInputState(text=initial_expr,
                         cursor_pos=len(initial_expr),
                         sel_end=len(initial_expr))
    cam = renderer.cam

    dragging   = False
    drag_last  = (0, 0)
    input_rect: Optional[pygame.Rect] = None
    btn_rect:   Optional[pygame.Rect] = None
    ar_rect:    Optional[pygame.Rect] = None

    running = True
    while running:
        dt = clock.tick(60)

        # auto-rotate
        if not cam.auto_rotate:
            cam.idle_timer += dt
            if cam.idle_timer >= cam.IDLE_DELAY:
                cam.auto_rotate = True
        if cam.auto_rotate:
            if cam.ease_t < 1.0:
                cam.ease_t = min(1.0, cam.ease_t + dt / 1500.0)
            t = cam.ease_t ** 2 * (3.0 - 2.0 * cam.ease_t)
            cam.rot_y += 0.006 * t

        # cursor blink
        inp.cur_timer += dt
        if inp.cur_timer >= 530:
            inp.cur_timer = 0
            inp.cur_vis = not inp.cur_vis

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
                break

            if event.type == pygame.VIDEORESIZE:
                W, H = event.w, event.h
                screen = pygame.display.set_mode((W, H), pygame.RESIZABLE)
                renderer.legend_surf = renderer._build_legend_surf()
                continue

            if event.type == pygame.KEYDOWN:
                ctrl  = pygame.key.get_mods() & pygame.KMOD_CTRL
                shift = pygame.key.get_mods() & pygame.KMOD_SHIFT

                if event.key == pygame.K_ESCAPE:
                    if inp.active:
                        inp.text = ''
                        inp.move_cursor(0, False)
                        renderer.load_expr('')
                    else:
                        running = False
                    continue

                if event.key == pygame.K_r and not inp.active:
                    cam.rot_x, cam.rot_y, cam.zoom = 0.2, 0.4, 1.0
                    continue

                if event.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
                    renderer.load_expr(inp.text)
                    renderer.info_surf = renderer._build_info_surf(None, [])
                    inp.active = False
                    continue

                consumed = handle_text_input_event(event, inp, input_rect)
                if consumed:
                    # live update
                    try:
                        renderer.load_expr(inp.text)
                    except Exception:
                        pass
                continue

            consumed = handle_text_input_event(event, inp, input_rect)
            if consumed:
                continue

            if event.type == pygame.MOUSEBUTTONDOWN:
                mx, my = event.pos
                shift  = pygame.key.get_mods() & pygame.KMOD_SHIFT

                if event.button == 1:
                    if my < TOP_H:
                        if btn_rect and btn_rect.collidepoint(mx, my):
                            renderer.load_expr(inp.text)
                            renderer.info_surf = renderer._build_info_surf(None, [])
                            inp.active = False
                        elif ar_rect and ar_rect.collidepoint(mx, my):
                            cam.auto_rotate = not cam.auto_rotate
                            cam.idle_timer  = 0
                            cam.ease_t = 0.0 if not cam.auto_rotate else 1.0
                        elif input_rect and input_rect.collidepoint(mx, my):
                            pass  # handled by handle_text_input_event
                        else:
                            inp.active = False
                    else:
                        inp.active = False
                        dragging   = True
                        drag_last  = (mx, my)
                        cam.auto_rotate = False
                        cam.idle_timer  = 0
                        cam.ease_t      = 0.0

                elif event.button == 3:
                    if my >= TOP_H:
                        renderer.selected  = renderer.node_at(mx, my)
                        renderer.info_surf = renderer._build_info_surf(
                            renderer.selected, renderer.relations)

                elif event.button == 4:
                    if my >= TOP_H: cam.zoom = min(5.0, cam.zoom * 1.1)
                elif event.button == 5:
                    if my >= TOP_H: cam.zoom = max(0.15, cam.zoom * 0.9)

            elif event.type == pygame.MOUSEBUTTONUP:
                if event.button == 1:
                    if dragging:
                        dragging = False
                        cam.idle_timer = 0
                        cam.ease_t = 0.0

            elif event.type == pygame.MOUSEMOTION:
                mx, my = event.pos
                if dragging:
                    dx = mx - drag_last[0]
                    dy = my - drag_last[1]
                    cam.rot_y += dx * 0.007
                    cam.rot_x += dy * 0.007
                    drag_last  = (mx, my)

        # Draw
        renderer.render_frame(screen)
        input_rect, btn_rect, ar_rect = draw_top_bar(
            screen, W, H, inp, cam.auto_rotate, input_label)
        pygame.display.flip()

    pygame.quit()


# ---------------------------------------------------------------------------
# Effect geometry data
# ---------------------------------------------------------------------------

EG_OP_INFO = {
    '*':     ('propagates',          (76,  175, 80),  True),
    '!':     ('excludes',            (244, 67,  54),  True),
    '~':     ('requires',            (33,  150, 243), True),
    '?':     ('weak propagation',    (255, 193, 7),   True),
    '@':     ('attenuatable',        (156, 39,  176), True),
    '!@':    ('permanent',           (233, 30,  99),  True),
    '^':     ('suppresses implied',  (96,  125, 139), True),
    '..':    ('one level up',        (0,   188, 212), True),
    '...':   ('indefinite',          (100, 181, 246), True),
    '&':     ('both',                (200, 200, 200), False),
    '|':     ('at least one',        (255, 152, 0),   False),
    '>':     ('priority',            (255, 87,  34),  False),
    '->':    ('implies',             (139, 195, 74),  False),
    '^|':    ('exclusive or',        (121, 85,  72),  False),
    '<->':   ('mutual implication',  (63,  81,  181), False),
    '_hier': ('hierarchy',           (60,  60,  60),  False),
    '_impl': ('built-in implies',    (80,  60,  100), False),
}

_EG_BUILTIN_CHILDREN = {
    'IO':        ['IO.Console', 'IO.File', 'IO.Socket', 'IO.Pipe',
                  'IO.Device', 'IO.Serial', 'IO.USB', 'IO.GPU'],
    'Alloc':     ['Alloc.Heap', 'Alloc.Pool', 'Alloc.Stack',
                  'Alloc.Virtual', 'Alloc.Shared'],
    'Unsafe':    ['Unsafe.Ptr', 'Unsafe.Cast', 'Unsafe.ASM',
                  'Unsafe.FFI', 'Unsafe.Uninit'],
    'Mem':       ['Mem.Read', 'Mem.Write', 'Mem.Exec'],
    'Mem.Read':  ['Mem.Read.Process', 'Mem.Read.Kernel', 'Mem.Read.Mapped'],
    'Mem.Write': ['Mem.Write.Process', 'Mem.Write.Kernel',
                  'Mem.Write.Exec', 'Mem.Write.Mapped'],
    'Mem.Exec':  ['Mem.Exec.JIT', 'Mem.Exec.Shellcode'],
    'Sync':      ['Sync.Lock', 'Sync.Atomic', 'Sync.Signal', 'Sync.Wait'],
    'Crypto':    ['Crypto.Hash', 'Crypto.Encrypt', 'Crypto.Decrypt',
                  'Crypto.Random', 'Crypto.Key'],
    'Process':   ['Process.Spawn', 'Process.Kill', 'Process.Inject',
                  'Process.Suspend', 'Process.Token'],
    'Hook':      ['Hook.Detour', 'Hook.IAT', 'Hook.SSDT',
                  'Hook.Vtable', 'Hook.Exception'],
    'Privilege': ['Privilege.Elevate', 'Privilege.Drop', 'Privilege.Check'],
    'Time':      ['Time.RealTime', 'Time.Sleep', 'Time.Timer'],
}
_EG_BUILTIN_PARENT = {c: p for p, cs in _EG_BUILTIN_CHILDREN.items() for c in cs}
_EG_BUILTIN_IMPLIES = {
    'Hook.Detour':    ['Hook', 'Unsafe', 'Mem.Write.Exec'],
    'Hook.IAT':       ['Hook', 'Mem.Write'],
    'Hook.SSDT':      ['Hook', 'Privilege', 'Mem.Write.Kernel', 'Unsafe'],
    'Hook.Vtable':    ['Hook', 'Mem.Write'],
    'Process.Inject': ['Process', 'Alloc.Virtual', 'Mem.Write.Exec', 'Hook', 'Unsafe'],
    'Crypto.Key':     ['Crypto'],
}
_EG_PERMANENT = {'Unsafe', 'Unsafe.Ptr', 'Unsafe.Cast', 'Unsafe.ASM',
                 'Unsafe.FFI', 'Unsafe.Uninit'}

_EG_OPERATORS = ['!@', '^|', '<->', '->', '..', '...', '*', '!', '~',
                 '?', '@', '^', '>', '&', '|']


@dataclass
class EGRelation:
    lhs: str
    op:  str
    rhs: str
    inferred: bool = False


def _eg_tokenize(expr: str):
    tokens, i = [], 0
    while i < len(expr):
        if expr[i].isspace(): i += 1; continue
        if expr[i] == '(': tokens.append(('(', 'LPAREN')); i += 1; continue
        if expr[i] == ')': tokens.append((')', 'RPAREN')); i += 1; continue
        matched = False
        for op in _EG_OPERATORS:
            if expr[i:i+len(op)] == op:
                tokens.append((op, 'OP')); i += len(op); matched = True; break
        if matched: continue
        if expr[i].isalpha() or expr[i] == '_':
            j = i
            while j < len(expr) and (expr[j].isalnum() or expr[j] in ('_', '.')):
                j += 1
            tokens.append((expr[i:j], 'IDENT')); i = j; continue
        i += 1
    return tokens


def parse_effect_expr(expr: str):
    tokens = _eg_tokenize(expr)
    relations, effect_names = [], set()
    idx = 0

    def peek(o=0):
        return tokens[idx + o] if idx + o < len(tokens) else None

    def consume():
        nonlocal idx
        t = tokens[idx]; idx += 1; return t

    def parse_atom():
        nonlocal idx
        t = peek()
        if t is None: return []
        if t[1] == 'LPAREN':
            consume()
            names = parse_list()
            if peek() and peek()[1] == 'RPAREN': consume()
            return names
        if t[1] == 'IDENT':
            consume(); effect_names.add(t[0]); return [t[0]]
        return []

    def parse_unary():
        t = peek()
        if t and t[1] == 'OP' and t[0] in {'*','!','~','?','@','!@','^','..','...'}:
            consume()
            names, _ = parse_unary()
            for n in names:
                relations.append(EGRelation(lhs=n, op=t[0], rhs=n))
            return names, t[0]
        names = parse_atom()
        return names, None

    def parse_list():
        lhs, _ = parse_unary()
        if not lhs: return []
        all_names = list(lhs)
        while peek() and peek()[1] == 'OP' and peek()[0] in {'&','|','>','->','^|','<->'}:
            op = consume()[0]
            rhs, _ = parse_unary()
            if not rhs: break
            for ln in lhs:
                for rn in rhs:
                    relations.append(EGRelation(lhs=ln, op=op, rhs=rn))
            all_names += [n for n in rhs if n not in all_names]
            lhs = rhs
        return all_names

    parse_list()
    return relations, effect_names


def _eg_infer(names: set) -> List[EGRelation]:
    inferred, seen = [], set()
    for name in names:
        p = _EG_BUILTIN_PARENT.get(name)
        if p and p in names:
            k = ('h', name, p)
            if k not in seen:
                seen.add(k)
                inferred.append(EGRelation(name, '_hier', p, True))
        for imp in _EG_BUILTIN_IMPLIES.get(name, []):
            if imp in names:
                k = ('i', name, imp)
                if k not in seen:
                    seen.add(k)
                    inferred.append(EGRelation(name, '_impl', imp, True))
    return inferred


def _eg_node_color(name: str):
    family = name.split('.')[0]
    h = (hash(family) % 360) / 360.0
    rv, gv, bv = colorsys.hsv_to_rgb(h, 0.60, 0.88)
    if name in _EG_PERMANENT:
        rv, gv, bv = colorsys.hsv_to_rgb(h, 0.30, 0.55)
    return (int(rv * 255), int(gv * 255), int(bv * 255))


# ---------------------------------------------------------------------------
# Effect geometry renderer
# ---------------------------------------------------------------------------

class EffectGeomRenderer(GraphRenderer):

    def _build_graph(self, expr: str):
        if not expr.strip():
            return [], [], 'Enter an effect expression'
        rels, names = parse_effect_expr(expr)
        inferred = _eg_infer(names)
        all_rels = rels + inferred
        name_list = sorted(names)
        pts   = sphere_layout(len(name_list))
        nodes = [GraphNode(nm, *pts[i]) for i, nm in enumerate(name_list)]
        n_perm = sum(1 for n in name_list if n in _EG_PERMANENT)
        status = (f'{len(name_list)} effects  |  {len(rels)} explicit  |  '
                  f'{len(inferred)} inferred  |  {n_perm} permanent')
        return nodes, all_rels, status

    def _draw_edges(self, surf, W, H):
        drawn_self = set()
        pair_groups: Dict[tuple, list] = {}
        self_rels = []

        for r in self.relations:
            if r.lhs == r.rhs:
                self_rels.append(r); continue
            ln = self.node_by_name(r.lhs)
            rn = self.node_by_name(r.rhs)
            if ln is None or rn is None: continue
            pair_groups.setdefault((r.lhs, r.rhs), []).append(r)

        # self-loop halos
        node_ops: Dict[str, list] = {}
        for r in self_rels:
            k = (r.lhs, r.op)
            if k in drawn_self: continue
            drawn_self.add(k)
            _, color, _ = EG_OP_INFO.get(r.op, ('', (150,150,150), False))
            node_ops.setdefault(r.lhs, []).append((r.op, color))

        for nname, ops in node_ops.items():
            node = self.node_by_name(nname)
            if node is None: continue
            dz = node.sz
            alpha = max(60, int(255 * (1.0 - max(0, (dz - 3.0) / 9.0) * 0.65)))
            nr  = int(NODE_RADIUS * max(0.5, min(1.3, 6.0 / dz)))
            ncx, ncy = int(node.sx), int(node.sy)
            label_r = nr + 22
            for i, (op, color) in enumerate(ops):
                fade = depth_fade_rgb(color, dz)
                if i == 0:
                    draw_aa_dashed_circle(surf, fade, ncx, ncy, nr + 12, alpha=alpha)
                angle = math.radians(-45 + i * (360 / len(ops)))
                lx = ncx + math.cos(angle) * label_r
                ly = ncy + math.sin(angle) * label_r
                tx = ncx + math.cos(angle) * (nr + 13)
                ty = ncy + math.sin(angle) * (nr + 13)
                draw_aa_line(surf, fade, tx, ty, lx, ly, 1, max(40, alpha - 60))
                draw_text(surf, op, lx, ly, size=depth_scaled_size(10, dz),
                          color=fade, anchor='center')

        # pairwise edges
        directed_ops = {'_hier', '_impl', '->'}
        for (nameA, nameB), entries in pair_groups.items():
            nA = self.node_by_name(nameA)
            nB = self.node_by_name(nameB)
            if nA is None or nB is None: continue
            x1, y1 = nA.sx, nA.sy
            x2, y2 = nB.sx, nB.sy
            dx, dy = x2 - x1, y2 - y1
            length = math.hypot(dx, dy) or 1
            px, py = -dy / length, dx / length
            avg_dz = (nA.sz + nB.sz) / 2
            alpha  = max(40, int(255 * (1.0 - max(0, (avg_dz - 3.0) / 9.0) * 0.65)))
            n = len(entries)
            fracs = [(i + 1) / (n + 1) for i in range(n)]
            for i, r in enumerate(entries):
                _, color, _ = EG_OP_INFO.get(r.op, ('', (150,150,150), False))
                fade  = depth_fade_rgb(color, avg_dz)
                la    = max(30, alpha - (70 if r.inferred else 0))
                width = 1 if r.inferred else 2
                offset = (i - (n - 1) / 2.0) * LANE_SPACING
                ax, ay = x1 + px * offset, y1 + py * offset
                bx, by = x2 + px * offset, y2 + py * offset
                ss = max(0.0, min(1.0, NODE_RADIUS / length))
                se = max(0.0, min(1.0, (length - NODE_RADIUS) / length))
                ssx, ssy = ax + (bx - ax) * ss, ay + (by - ay) * ss
                eex, eey = ax + (bx - ax) * se, ay + (by - ay) * se
                draw_arrow_single(surf, fade, ssx, ssy, eex, eey,
                                  width=width, alpha=la, dash=r.inferred,
                                  directed=(r.op in directed_ops))
                t  = fracs[i]
                lx = ax + (bx - ax) * t + px * 13
                ly = ay + (by - ay) * t + py * 13
                lbl = r.op if not r.op.startswith('_') else \
                      ('hier' if r.op == '_hier' else 'impl')
                lc = fade if not r.inferred else (60, 60, 60)
                draw_text(surf, lbl, lx, ly,
                          size=depth_scaled_size(10, avg_dz),
                          color=lc, anchor='center')

    def _draw_node(self, surf, node, W, H):
        dz    = node.sz
        scale = max(0.5, min(1.3, 6.0 / dz))
        nr    = int(NODE_RADIUS * scale)
        ncx, ncy = int(node.sx), int(node.sy)
        alpha = max(80, int(255 * (1.0 - max(0, (dz - 3.0) / 9.0) * 0.55)))
        base  = _eg_node_color(node.name)
        fade  = depth_fade_rgb(base, dz)
        is_sel  = self.selected is not None and self.selected.name == node.name
        is_perm = node.name in _EG_PERMANENT
        if is_sel:
            for rr in range(nr + 8, nr + 3, -1):
                a = max(0, int(60 * (1 - (rr - nr) / 8.0)))
                pygame.gfxdraw.aacircle(surf, ncx, ncy, rr, (255, 255, 255, a))
        if is_perm:
            pygame.gfxdraw.aacircle(surf, ncx, ncy, max(2, nr - 4),
                                    (233, 30, 99, max(40, alpha - 40)))
        draw_aa_circle(surf, fade, ncx, ncy, nr, alpha=alpha)
        outline = (255, 255, 255) if is_sel else (80, 80, 80)
        pygame.gfxdraw.aacircle(surf, ncx, ncy, nr, (*outline, alpha))
        parts = node.name.split('.')
        lbl_size = depth_scaled_size(9 if len(parts) > 1 else 11, dz)
        if len(parts) == 1:
            draw_text(surf, node.name, ncx, ncy, size=lbl_size,
                      bold=True, color=(255, 255, 255), anchor='center')
        else:
            draw_text(surf, parts[0], ncx, ncy - lbl_size // 2 - 1,
                      size=lbl_size, bold=True, color=(200, 200, 200), anchor='center')
            draw_text(surf, '.' + '.'.join(parts[1:]),
                      ncx, ncy + lbl_size // 2 + 1,
                      size=lbl_size, color=(255, 255, 255), anchor='center')

    def _build_legend_surf(self) -> pygame.Surface:
        w, h = PANEL_W, CANVAS_H - TOP_H
        surf = pygame.Surface((w, h), pygame.SRCALPHA)
        surf.fill((22, 22, 22, 245))
        y = 12
        draw_text(surf, 'Effect Operators', 10, y, size=13, bold=True,
                  color=(210, 210, 210), anchor='topleft')
        y += 22

        def section(title, ops):
            nonlocal y
            draw_text(surf, title, 10, y, size=10, bold=True,
                      color=(130, 130, 130), anchor='topleft')
            y += 15
            for op in ops:
                if op not in EG_OP_INFO: continue
                meaning, color, _ = EG_OP_INFO[op]
                pygame.draw.rect(surf, color, (10, y - 1, 6, 12))
                lbl = op if not op.startswith('_') else \
                      ('hierarchy' if op == '_hier' else 'built-in implies')
                draw_text(surf, lbl, 22, y, size=10, bold=True,
                          color=color, anchor='topleft')
                draw_text(surf, meaning,
                          22 + max(40, get_font(10, True).size(lbl)[0] + 6),
                          y, size=9, color=(100, 100, 100), anchor='topleft')
                y += 15
            y += 4

        section('Unary (self-loop)', ['*','!','~','?','@','!@','^','..','...'])
        pygame.draw.line(surf, (45, 45, 45), (8, y), (w - 8, y)); y += 6
        section('Binary (edge)',     ['&','|','>','->','^|','<->'])
        pygame.draw.line(surf, (45, 45, 45), (8, y), (w - 8, y)); y += 6
        section('Inferred',          ['_hier', '_impl'])

        pygame.draw.line(surf, (55, 55, 55), (8, y), (w - 8, y)); y += 8
        draw_text(surf, 'Controls', 10, y, size=12, bold=True,
                  color=(180, 180, 180), anchor='topleft'); y += 18
        for txt in ['LMB drag: rotate', 'Scroll: zoom',
                    'RMB: select node', 'R: reset', 'Enter: visualize']:
            draw_text(surf, txt, 10, y, size=10, color=(90, 90, 90), anchor='topleft')
            y += 14
        pygame.draw.line(surf, (55, 55, 55), (8, y), (w - 8, y)); y += 8
        draw_text(surf, 'Darker nodes = !@ permanent', 10, y, size=9,
                  color=(80, 80, 80), anchor='topleft')
        return surf

    def _build_info_surf(self, node, relations) -> pygame.Surface:
        w, h = PANEL_W, 220
        surf = pygame.Surface((w, h), pygame.SRCALPHA)
        surf.fill((22, 22, 22, 0))
        if node is None:
            draw_text(surf, 'RMB a node to inspect', 8, 8, size=10,
                      color=(80, 80, 80), anchor='topleft')
            return surf
        y = 8
        nc = (180, 140, 255) if node.name in _EG_PERMANENT else (180, 210, 255)
        draw_text(surf, f'Effect: {node.name}', 8, y, size=12,
                  bold=True, color=nc, anchor='topleft'); y += 16
        p = _EG_BUILTIN_PARENT.get(node.name)
        if p:
            draw_text(surf, f'Parent: {p}', 8, y, size=10,
                      color=(100, 160, 100), anchor='topleft'); y += 14
        ch = _EG_BUILTIN_CHILDREN.get(node.name, [])
        if ch:
            draw_text(surf, f'Children: {", ".join(ch)}', 8, y, size=9,
                      color=(80, 120, 80), anchor='topleft'); y += 14
        imp = _EG_BUILTIN_IMPLIES.get(node.name, [])
        if imp:
            draw_text(surf, f'Implies: {", ".join(imp)}', 8, y, size=9,
                      color=(140, 100, 180), anchor='topleft'); y += 14
        if node.name in _EG_PERMANENT:
            draw_text(surf, '!@ permanent', 8, y, size=9,
                      color=(233, 30, 99), anchor='topleft'); y += 14
        pygame.draw.line(surf, (50, 50, 50), (8, y), (w - 16, y)); y += 6
        draw_text(surf, 'Relations:', 8, y, size=10, bold=True,
                  color=(150, 150, 150), anchor='topleft'); y += 14
        for r in (relations or self.relations):
            if r.lhs != node.name and r.rhs != node.name: continue
            _, color, _ = EG_OP_INFO.get(r.op, ('', (200, 200, 200), False))
            if r.lhs == r.rhs:
                tag = f'{r.op} {r.lhs}'
            else:
                tag = f'{r.lhs} {r.op} {r.rhs}'
            if r.inferred:
                color = tuple(max(0, c - 60) for c in color)
                tag += ' (inf)'
            draw_text(surf, tag, 8, y, size=9, color=color, anchor='topleft')
            y += 12
            if y > h - 14: break
        return surf


# ---------------------------------------------------------------------------
# Type geometry data (from tg.py)
# ---------------------------------------------------------------------------

TG_OP_INFO = {
    '~=':   ('compatible',          (76,  175, 80),  False),
    '!~=':  ('incompatible',        (244, 67,  54),  False),
    '!@':   ('no address-of',       (255, 152, 0),   True),
    '!`<':  ('no narrowing',        (156, 39,  176), True),
    '!`<=': ('no narrowing (pair)', (123, 31,  162), False),
    '!`>':  ('no widening',         (33,  150, 243), True),
    '!`>=': ('no widening (pair)',  (21,  101, 192), False),
    '!-=':  ('no signed ops',       (96,  125, 139), False),
}

_TG_OPERATORS = ['!`<=', '!`>=', '!~=', '!-=', '!`<', '!`>', '~=', '!@']


@dataclass
class TGRelation:
    lhs:           list
    op:            str
    rhs:           str
    inferred:      bool = False
    bracket_group: bool = False


def _tg_tokenize(expr: str):
    tokens, i = [], 0
    while i < len(expr):
        if expr[i].isspace(): i += 1; continue
        if expr[i] == '[': tokens.append(('[', 'LBRACKET')); i += 1; continue
        if expr[i] == ']': tokens.append((']', 'RBRACKET')); i += 1; continue
        if expr[i] == '&': tokens.append(('&', 'AMP')); i += 1; continue
        matched = False
        for op in _TG_OPERATORS:
            if expr[i:i+len(op)] == op:
                tokens.append((op, 'OP')); i += len(op); matched = True; break
        if matched: continue
        if expr[i].isalpha() or expr[i] == '_':
            j = i
            while j < len(expr) and (expr[j].isalnum() or expr[j] == '_'): j += 1
            tokens.append((expr[i:j], 'IDENT')); i = j; continue
        i += 1
    return tokens


def parse_type_expr(expr: str):
    tokens = _tg_tokenize(expr)
    relations, type_names = [], set()
    idx = 0

    def peek(o=0):
        return tokens[idx + o] if idx + o < len(tokens) else None

    def consume():
        nonlocal idx
        t = tokens[idx]; idx += 1; return t

    def is_op():
        t = peek()
        return t is not None and t[1] == 'OP'

    def consume_op():
        return consume()[0]

    def parse_id_list():
        nonlocal idx
        names = []
        t = peek()
        if t is None or t[1] != 'IDENT': return names
        names.append(t[0]); type_names.add(t[0]); idx += 1
        while peek() and peek()[1] == 'AMP':
            nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
            if nxt and nxt[1] == 'IDENT':
                idx += 1; names.append(nxt[0]); type_names.add(nxt[0]); idx += 1
            else: break
        return names

    def parse_bracket():
        nonlocal idx
        idx += 1
        sub_lhs = parse_id_list()
        all_names = list(sub_lhs)
        while is_op():
            op = consume_op()
            in_brk = peek() and peek()[1] == 'LBRACKET'
            sub_rhs = parse_bracket() if in_brk else parse_id_list()
            all_names += [n for n in sub_rhs if n not in all_names]
            ind = TG_OP_INFO.get(op, ('', (255,255,255), False))[2]
            if ind:
                for n in sub_lhs: relations.append(TGRelation([n], op, n, bracket_group=True))
                for n in sub_rhs: relations.append(TGRelation([n], op, n, bracket_group=True))
            else:
                for ln in sub_lhs:
                    for rn in sub_rhs:
                        relations.append(TGRelation([ln], op, rn, bracket_group=True))
            sub_lhs = sub_rhs
        if peek() and peek()[1] == 'RBRACKET': idx += 1
        return all_names

    def parse_segment():
        nonlocal idx
        if peek() and peek()[1] == 'LBRACKET':
            return parse_bracket(), True
        names = parse_id_list()
        is_brk = False
        while peek() and peek()[1] == 'AMP':
            nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
            if nxt and nxt[1] == 'LBRACKET':
                idx += 1
                brk = parse_bracket()
                names += [n for n in brk if n not in names]
                is_brk = True
            elif nxt and nxt[1] == 'IDENT':
                idx += 1; names += parse_id_list()
            else: break
        return names, is_brk

    lhs, lhs_brk = parse_segment()
    if not lhs: return relations, type_names
    while is_op():
        op = consume_op()
        rhs, rhs_brk = parse_segment()
        if not rhs: break
        ind = TG_OP_INFO.get(op, ('', (255,255,255), False))[2]
        if ind:
            for n in lhs: relations.append(TGRelation([n], op, n, bracket_group=lhs_brk))
            for n in rhs: relations.append(TGRelation([n], op, n, bracket_group=rhs_brk))
        else:
            for ln in lhs:
                for rn in rhs:
                    relations.append(TGRelation([ln], op, rn,
                                                bracket_group=lhs_brk or rhs_brk))
        lhs, lhs_brk = rhs, rhs_brk
    return relations, type_names


def _tg_infer(relations, type_names):
    incompat, compat = set(), set()
    explicit: Dict[tuple, set] = {}
    for r in relations:
        if r.inferred: continue
        key = tuple(sorted([r.lhs[0], r.rhs]))
        explicit.setdefault(key, set()).add(r.op)
        if r.op == '!~=': incompat.add(key)
        elif r.op == '~=': compat.add(key)

    inferred = []
    names = sorted(type_names)  # deterministic order

    # Keep inferring until no new relations are added (fixed point)
    changed = True
    while changed:
        changed = False
        for i, a in enumerate(names):
            for j, b in enumerate(names):
                if j == i: continue
                for k, c in enumerate(names):
                    if k == i or k == j: continue
                    ab = tuple(sorted([a, b]))
                    bc = tuple(sorted([b, c]))
                    ac = tuple(sorted([a, c]))
                    # If a!~=b and b!~=c, then a~=c by transitivity of incompatibility
                    if ab in incompat and bc in incompat and ac not in compat:
                        if '!~=' not in explicit.get(ac, set()):
                            inferred.append(TGRelation([a], '~=', c, inferred=True))
                            compat.add(ac)
                            changed = True
    return inferred


def _tg_node_color(name: str):
    h = (hash(name) % 360) / 360.0
    rv, gv, bv = colorsys.hsv_to_rgb(h, 0.65, 0.90)
    return (int(rv * 255), int(gv * 255), int(bv * 255))


# ---------------------------------------------------------------------------
# Type geometry renderer
# ---------------------------------------------------------------------------

class TypeGeomRenderer(GraphRenderer):

    BG = (18, 18, 20)

    def _build_graph(self, expr: str):
        if not expr.strip():
            return [], [], 'Enter a type constraint expression'
        rels, names = parse_type_expr(expr)
        inferred = _tg_infer(rels, names)
        all_rels = rels + inferred
        name_list = sorted(names)
        pts   = sphere_layout(len(name_list))
        nodes = [GraphNode(nm, *pts[i]) for i, nm in enumerate(name_list)]
        status = (f'{len(name_list)} types  |  {len(rels)} explicit  |  '
                  f'{len(inferred)} inferred  |  drag=rotate  scroll=zoom  R=reset')
        return nodes, all_rels, status

    def _draw_edges(self, surf, W, H):
        drawn_self = set()
        pair_groups: Dict[tuple, list] = {}
        self_rels = []

        for r in self.relations:
            if r.lhs[0] == r.rhs:
                self_rels.append(r); continue
            ln = self.node_by_name(r.lhs[0])
            rn = self.node_by_name(r.rhs)
            if ln is None or rn is None: continue
            key = tuple(sorted([r.lhs[0], r.rhs]))
            pair_groups.setdefault(key, []).append((r, r.lhs[0] == key[0]))

        # self-loop halos
        node_ops: Dict[str, list] = {}
        for r in self_rels:
            k2 = (r.lhs[0], r.op)
            if k2 in drawn_self: continue
            drawn_self.add(k2)
            _, color, _ = TG_OP_INFO.get(r.op, ('', (150,150,150), False))
            node_ops.setdefault(r.lhs[0], []).append((r.op, color))

        for nname, ops in node_ops.items():
            node = self.node_by_name(nname)
            if node is None: continue
            dz = node.sz
            alpha = max(60, int(255 * (1.0 - max(0, (dz - 3.0) / 9.0) * 0.65)))
            nr  = int(NODE_RADIUS * max(0.5, min(1.3, 6.0 / dz)))
            ncx, ncy = int(node.sx), int(node.sy)
            label_r = nr + 22
            for i, (op, color) in enumerate(ops):
                fade = depth_fade_rgb(color, dz, bg=(30, 30, 30))
                if i == 0:
                    draw_aa_dashed_circle(surf, fade, ncx, ncy, nr + 12, alpha=alpha)
                angle = math.radians(-45 + i * (360 / len(ops)))
                lx = ncx + math.cos(angle) * label_r
                ly = ncy + math.sin(angle) * label_r
                tx = ncx + math.cos(angle) * (nr + 13)
                ty = ncy + math.sin(angle) * (nr + 13)
                draw_aa_line(surf, fade, tx, ty, lx, ly, 1, max(40, alpha - 60))
                draw_text(surf, op, lx, ly, size=depth_scaled_size(10, dz),
                          color=fade, anchor='center')

        # pairwise
        for (nameA, nameB), entries in pair_groups.items():
            nA = self.node_by_name(nameA)
            nB = self.node_by_name(nameB)
            if nA is None or nB is None: continue
            x1, y1 = nA.sx, nA.sy
            x2, y2 = nB.sx, nB.sy
            dx, dy = x2 - x1, y2 - y1
            length = math.hypot(dx, dy) or 1
            px, py = -dy / length, dx / length
            avg_dz = (nA.sz + nB.sz) / 2
            alpha  = max(40, int(255 * (1.0 - max(0, (avg_dz - 3.0) / 9.0) * 0.65)))
            n = len(entries)
            fracs = [(i + 1) / (n + 1) for i in range(n)]
            for i, (r, _fwd) in enumerate(entries):
                _, color, _ = TG_OP_INFO.get(r.op, ('', (150,150,150), False))
                fade  = depth_fade_rgb(color, avg_dz, bg=(30, 30, 30))
                la    = max(30, alpha - (60 if r.inferred else 0))
                width = 1 if r.inferred else 2
                offset = (i - (n - 1) / 2.0) * LANE_SPACING
                ax, ay = x1 + px * offset, y1 + py * offset
                bx, by = x2 + px * offset, y2 + py * offset
                ss = max(0.0, min(1.0, NODE_RADIUS / length))
                se = max(0.0, min(1.0, (length - NODE_RADIUS) / length))
                ssx, ssy = ax + (bx - ax) * ss, ay + (by - ay) * ss
                eex, eey = ax + (bx - ax) * se, ay + (by - ay) * se
                draw_arrow_double(surf, fade, ssx, ssy, eex, eey,
                                  width=width, alpha=la, dash=r.inferred)
                t  = fracs[i]
                lx = ax + (bx - ax) * t + px * 13
                ly = ay + (by - ay) * t + py * 13
                lc = fade if not r.inferred else (70, 70, 70)
                draw_text(surf, r.op, lx, ly,
                          size=depth_scaled_size(10, avg_dz),
                          color=lc, anchor='center')
                if r.bracket_group:
                    lbl_size = depth_scaled_size(10, avg_dz)
                    draw_text(surf, '[grp]', lx, ly + lbl_size + 3,
                              size=max(7, lbl_size - 2), color=(60, 60, 60), anchor='center')

    def _draw_node(self, surf, node, W, H):
        dz    = node.sz
        scale = max(0.5, min(1.3, 6.0 / dz))
        nr    = int(NODE_RADIUS * scale)
        ncx, ncy = int(node.sx), int(node.sy)
        alpha = max(80, int(255 * (1.0 - max(0, (dz - 3.0) / 9.0) * 0.55)))
        base  = _tg_node_color(node.name)
        fade  = depth_fade_rgb(base, dz, bg=(30, 30, 30))
        is_sel = self.selected is not None and self.selected.name == node.name
        if is_sel:
            for rr in range(nr + 8, nr + 3, -1):
                a = max(0, int(60 * (1 - (rr - nr) / 8.0)))
                pygame.gfxdraw.aacircle(surf, ncx, ncy, rr, (255, 255, 255, a))
        draw_aa_circle(surf, fade, ncx, ncy, nr, alpha=alpha)
        outline = (255, 255, 255) if is_sel else (80, 80, 80)
        pygame.gfxdraw.aacircle(surf, ncx, ncy, nr, (*outline, alpha))
        draw_text(surf, node.name, ncx, ncy, size=14, bold=True,
                  color=(255, 255, 255), anchor='center')

    def _build_legend_surf(self) -> pygame.Surface:
        w, h = PANEL_W, CANVAS_H - TOP_H
        surf = pygame.Surface((w, h), pygame.SRCALPHA)
        surf.fill((22, 22, 22, 245))
        y = 12
        draw_text(surf, 'Operators', 10, y, size=13, bold=True,
                  color=(210, 210, 210), anchor='topleft'); y += 22
        for op, (meaning, color, ind) in TG_OP_INFO.items():
            pygame.draw.rect(surf, color, (10, y - 1, 6, 13))
            scope = ' [ind]' if ind else ''
            draw_text(surf, op, 22, y, size=11, bold=True, color=color, anchor='topleft')
            draw_text(surf, meaning + scope, 72, y, size=10,
                      color=(130, 130, 130), anchor='topleft')
            y += 16
        y += 4
        pygame.draw.line(surf, (55, 55, 55), (8, y), (w - 8, y)); y += 8
        draw_text(surf, '-- inferred relation', 10, y, size=10,
                  color=(80, 80, 80), anchor='topleft'); y += 15
        draw_text(surf, '[ ] bracket group', 10, y, size=10,
                  color=(100, 100, 100), anchor='topleft'); y += 20
        pygame.draw.line(surf, (55, 55, 55), (8, y), (w - 8, y)); y += 8
        draw_text(surf, 'Controls', 10, y, size=12, bold=True,
                  color=(180, 180, 180), anchor='topleft'); y += 18
        for txt in ['LMB drag: rotate', 'Scroll: zoom',
                    'RMB: select node', 'R: reset', 'Enter: visualize']:
            draw_text(surf, txt, 10, y, size=10, color=(90, 90, 90), anchor='topleft')
            y += 14
        return surf

    def _build_info_surf(self, node, relations) -> pygame.Surface:
        w, h = PANEL_W, 200
        surf = pygame.Surface((w, h), pygame.SRCALPHA)
        surf.fill((22, 22, 22, 0))
        if node is None:
            draw_text(surf, 'RMB a node to inspect', 8, 8, size=10,
                      color=(80, 80, 80), anchor='topleft')
            return surf
        y = 8
        draw_text(surf, f'Type: {node.name}', 8, y, size=12, bold=True,
                  color=(180, 210, 255), anchor='topleft'); y += 20
        rels = relations or self.relations
        for r in rels:
            if node.name not in r.lhs and node.name != r.rhs: continue
            _, color, _ = TG_OP_INFO.get(r.op, ('', (200, 200, 200), False))
            tag  = ' (inf)' if r.inferred else ''
            tag2 = ' [brk]' if r.bracket_group else ''
            if r.lhs[0] == r.rhs:
                line = f'{r.lhs[0]} {r.op}{tag}{tag2}'
            else:
                line = f'{r.lhs[0]} {r.op} {r.rhs}{tag}{tag2}'
            draw_text(surf, line, 8, y, size=10, color=color, anchor='topleft'); y += 13
            _, meaning, _ = TG_OP_INFO.get(r.op, ('', (200, 200, 200), False))
            draw_text(surf, f'  -> {meaning}', 8, y, size=9,
                      color=(90, 90, 90), anchor='topleft'); y += 13
            if y > h - 16: break
        return surf


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def _ensure_pygame_display():
    """
    Init pygame for headless offscreen rendering if no display is open.
    Uses the null SDL driver on platforms where no display is available.
    """
    if not pygame.get_init():
        import os
        if 'SDL_VIDEODRIVER' not in os.environ:
            # don't override if the caller already set it
            pass
        pygame.init()


def render_effect_frame(expr: str, w: int = 400, h: int = 300,
                        rot_x: float = 0.3, rot_y: float = 0.6,
                        zoom: float = 0.9) -> pygame.Surface:
    """
    Render one frame of the effect geometry graph into an offscreen surface.
    Safe to call from any thread after pygame.init().
    """
    r = EffectGeomRenderer()
    r.cam.rot_x, r.cam.rot_y, r.cam.zoom = rot_x, rot_y, zoom
    r.load_expr(expr)
    return r.mini_frame(w, h)


def render_type_frame(expr: str, w: int = 400, h: int = 300,
                      rot_x: float = 0.3, rot_y: float = 0.6,
                      zoom: float = 0.9) -> pygame.Surface:
    """
    Render one frame of the type geometry graph into an offscreen surface.
    """
    r = TypeGeomRenderer()
    r.cam.rot_x, r.cam.rot_y, r.cam.zoom = rot_x, rot_y, zoom
    r.load_expr(expr)
    return r.mini_frame(w, h)


def launch_effect_full(expr: str = ''):
    """Open a full interactive effect geometry window. Blocks until closed."""
    run_interactive(EffectGeomRenderer(),
                    'Flux Effect Geometry Visualizer',
                    'Effect expr:', expr)


def launch_type_full(expr: str = ''):
    """Open a full interactive type geometry window. Blocks until closed."""
    run_interactive(TypeGeomRenderer(),
                    'Flux Type Geometry Visualizer',
                    'Constraint:', expr)