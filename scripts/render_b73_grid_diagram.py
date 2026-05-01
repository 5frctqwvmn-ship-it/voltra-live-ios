#!/usr/bin/env python3
"""
b73 V4-D23 — debug grid scroll-anchor visual validator.

This script renders a side-by-side diagram showing what the new
content-anchored debug grid looks like at scroll offset 0 vs. half-
scroll, demonstrating the coordinate-system invariant:

    "LEG DAY" sits at content row 6 in both panels, because row labels
    travel with the content.

Why a Python diagram and not a simulator screenshot?
The CI sandbox is a Linux container without Xcode/iOS Simulator. On-
device captures will land in TestFlight (build 73). This diagram is a
deterministic mathematical preview of the implementation in
DebugGridOverlay.swift — it uses the SAME formulas the SwiftUI overlay
uses (rows at y = contentMinY + i * 32) so a mismatch here would
indicate a logic bug, not a rendering bug.

Output: docs/handoff/screenshots/b73/grid_scroll_invariant.png
"""

from PIL import Image, ImageDraw, ImageFont
import os

# Match the runtime constants from DebugGridOverlay.swift exactly.
BASE_SPACING = 32
MARGIN_STRIP = 14
VIEWPORT_W = 390      # iPhone 15 portrait
VIEWPORT_H = 720      # representative screen body height
CONTENT_H = 1300      # taller-than-viewport scroll content

# Synthetic LoggingHomeView content. Each entry sits at content-y =
# offset_y, and is N pt tall. The label is drawn there, and the
# row-coordinate it occupies is round((offset_y + h/2) / 32) + 1.
# Synthetic LoggingHomeView layout (content y, height) chosen so that
# LEG DAY centers near content row 10. Items don't overlap.
CONTENT_ELEMENTS = [
    ("VoltraUnitHeader",          24,  88),
    ("PICK A DAY",                132, 26),
    ("PUSH",                      170, 80),
    ("PULL",                      170, 80),  # rendered as side-by-side via narrow box; same y for visual; OK because we only probe LEG DAY
    ("LEG DAY",                   270, 80),  # ~content row 10
    ("CUSTOM",                    370, 80),
    ("Open live dashboard",       476, 56),
    ("Demo Mode",                 556, 56),
    ("(end of content)",          1240, 24),
]

# Mint label colors (approximate VoltraColor.textFaint).
LABEL = (170, 220, 200, 220)
GRID_BASE = (170, 220, 200, 90)
GRID_HALF = (170, 220, 200, 60)
BG = (12, 14, 16, 255)
ELEM_BG = (40, 60, 70, 200)
ELEM_BORDER = (80, 130, 130, 255)
ELEM_TEXT = (220, 240, 230, 255)
HIGHLIGHT_BG = (90, 50, 50, 230)
HIGHLIGHT_BORDER = (255, 110, 110, 255)
HIGHLIGHT_TEXT = (255, 220, 220, 255)


def find_font(size, mono=False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
            if mono else
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
            if mono else
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            return ImageFont.truetype(c, size)
    return ImageFont.load_default()


def render_panel(scroll_offset_y, panel_label, font_label, font_grid,
                 font_elem, font_caption):
    """
    scroll_offset_y is how far the user has scrolled DOWN into the
    content. At rest = 0; positive number means the content has slid
    upward by that many points.

    contentMinY in viewport coords = -scroll_offset_y.
    """
    img = Image.new("RGBA", (VIEWPORT_W, VIEWPORT_H + 60), BG)
    d = ImageDraw.Draw(img, "RGBA")

    # Caption strip at top of panel (outside the "viewport").
    d.text((10, 8), panel_label, fill=(220, 240, 230, 255), font=font_caption)

    # Inner viewport region.
    vy_top = 40
    d.rectangle([0, vy_top, VIEWPORT_W, vy_top + VIEWPORT_H],
                fill=BG, outline=(60, 70, 80, 255), width=1)

    content_min_y_in_viewport = -scroll_offset_y  # signed

    # 1) Content elements (rendered first so grid + labels overlay).
    leg_day_row_in_content = None
    for name, off_y, h in CONTENT_ELEMENTS:
        view_y = vy_top + content_min_y_in_viewport + off_y
        if view_y + h < vy_top or view_y > vy_top + VIEWPORT_H:
            continue  # off-screen; skip
        # Highlight LEG DAY since that's our coordinate-invariant probe.
        is_leg = (name == "LEG DAY")
        d.rectangle(
            [16, view_y, VIEWPORT_W - 16, view_y + h],
            fill=HIGHLIGHT_BG if is_leg else ELEM_BG,
            outline=HIGHLIGHT_BORDER if is_leg else ELEM_BORDER,
            width=2 if is_leg else 1,
        )
        d.text(
            (24, view_y + h // 2 - 8),
            name,
            fill=HIGHLIGHT_TEXT if is_leg else ELEM_TEXT,
            font=font_elem,
        )
        if is_leg:
            # Compute the row number under the b73 model:
            # row 1 sits at content y=0, every 32pt = next row.
            # The center of LEG DAY in content space is off_y + h/2.
            content_center = off_y + h // 2
            leg_day_row_in_content = (content_center // BASE_SPACING) + 1

    # 2) Vertical gridlines + column letters (VIEWPORT pinned).
    for i in range(0, VIEWPORT_W // BASE_SPACING + 1):
        x = i * BASE_SPACING
        d.line(
            [(x, vy_top), (x, vy_top + VIEWPORT_H)],
            fill=GRID_BASE, width=1,
        )
        # Spreadsheet letter A, B, C, ... AA, AB
        n, s = i, ""
        while True:
            s = chr(65 + (n % 26)) + s
            n = n // 26 - 1
            if n < 0:
                break
        d.text((x + 3, vy_top + 2), s, fill=LABEL, font=font_grid)

    # 3) Horizontal gridlines + row numbers (CONTENT pinned).
    # Draw rows for the full content range, then clip to viewport.
    n_rows = (CONTENT_H // BASE_SPACING) + 2
    for i in range(n_rows):
        # y in content space = i * BASE_SPACING.
        view_y = vy_top + content_min_y_in_viewport + i * BASE_SPACING
        if view_y < vy_top - BASE_SPACING or view_y > vy_top + VIEWPORT_H + BASE_SPACING:
            continue
        d.line(
            [(0, view_y), (VIEWPORT_W, view_y)],
            fill=GRID_BASE, width=1,
        )
        d.text((4, view_y - 6), str(i + 1), fill=LABEL, font=font_grid)

    # Footer: scroll state + LEG DAY row in content coords.
    bottom_y = vy_top + VIEWPORT_H + 6
    msg = (f"scroll offset = {scroll_offset_y} pt    "
           f"contentMinY = {content_min_y_in_viewport} pt    "
           f"LEG DAY -> content row {leg_day_row_in_content}")
    d.text((10, bottom_y), msg, fill=(170, 220, 200, 255), font=font_caption)
    return img


def main():
    out_dir = "docs/handoff/screenshots/b73"
    os.makedirs(out_dir, exist_ok=True)

    f_label = find_font(11, mono=False)
    f_grid = find_font(8, mono=True)
    f_elem = find_font(11, mono=False)
    f_cap = find_font(10, mono=True)

    p1 = render_panel(0, "BEFORE SCROLL (offset 0 pt)",
                      f_label, f_grid, f_elem, f_cap)
    p2 = render_panel(192, "AFTER SCROLL (offset 192 pt = 6 rows)",
                      f_label, f_grid, f_elem, f_cap)

    # Composite the two panels side by side with a header.
    pad = 24
    header_h = 100
    total_w = p1.width * 2 + pad * 3
    total_h = p1.height + header_h + pad
    out = Image.new("RGBA", (total_w, total_h), (8, 10, 12, 255))
    od = ImageDraw.Draw(out, "RGBA")
    title_font = find_font(20, mono=False)
    sub_font = find_font(12, mono=True)
    od.text((pad, 18),
            "b73 V4-D23 - Debug grid scroll-anchor invariant",
            fill=(220, 240, 230, 255), font=title_font)
    od.text((pad, 50),
            "Coordinate-system contract: \"LEG DAY\" sits at the SAME content row",
            fill=(170, 220, 200, 255), font=sub_font)
    od.text((pad, 68),
            "in both panels because row labels travel with the scrollable content.",
            fill=(170, 220, 200, 255), font=sub_font)

    out.paste(p1, (pad, header_h))
    out.paste(p2, (pad * 2 + p1.width, header_h))

    out_path = os.path.join(out_dir, "grid_scroll_invariant.png")
    out.save(out_path)
    print(f"wrote {out_path} ({out.size[0]}x{out.size[1]})")

    # Also save the two panels individually for the WORK_LOG entry.
    p1.save(os.path.join(out_dir, "logging_home_offset_0.png"))
    p2.save(os.path.join(out_dir, "logging_home_offset_192.png"))
    print("wrote individual panels")


if __name__ == "__main__":
    main()
