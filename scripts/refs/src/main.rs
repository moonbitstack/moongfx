//! Draws the reference scenes with tiny-skia and writes them as PNG.
//!
//! The MoonBit conformance test in `integration/` draws the same scenes with
//! `moongfx/soft` and compares the two, so every number here has a twin there.
//! Run from the repository root: `cargo run --release --manifest-path scripts/refs/Cargo.toml`.

use tiny_skia::{
    Color, FillRule, LineCap, LineJoin, Paint, Path, PathBuilder, Pixmap, Point, Rect,
    SpreadMode, Stroke, Transform,
};

const SIZE: u32 = 256;

fn rgba(r: u8, g: u8, b: u8, a: u8) -> Color {
    Color::from_rgba8(r, g, b, a)
}

fn solid(color: Color) -> Paint<'static> {
    let mut paint = Paint::default();
    paint.set_color(color);
    paint.anti_alias = true;
    paint
}

fn rect_path(x: f32, y: f32, w: f32, h: f32, reversed: bool) -> Path {
    let mut pb = PathBuilder::new();
    if reversed {
        pb.move_to(x, y);
        pb.line_to(x, y + h);
        pb.line_to(x + w, y + h);
        pb.line_to(x + w, y);
    } else {
        pb.move_to(x, y);
        pb.line_to(x + w, y);
        pb.line_to(x + w, y + h);
        pb.line_to(x, y + h);
    }
    pb.close();
    pb.finish().unwrap()
}

fn circle_path(cx: f32, cy: f32, r: f32, reversed: bool) -> Path {
    // Four cubic steps, the same approximation the MoonBit side uses for an
    // ellipse; a circle is one with both radii equal.
    let k = 0.5522847498307936 * r;
    let mut pb = PathBuilder::new();
    if reversed {
        pb.move_to(cx + r, cy);
        pb.cubic_to(cx + r, cy - k, cx + k, cy - r, cx, cy - r);
        pb.cubic_to(cx - k, cy - r, cx - r, cy - k, cx - r, cy);
        pb.cubic_to(cx - r, cy + k, cx - k, cy + r, cx, cy + r);
        pb.cubic_to(cx + k, cy + r, cx + r, cy + k, cx + r, cy);
    } else {
        pb.move_to(cx + r, cy);
        pb.cubic_to(cx + r, cy + k, cx + k, cy + r, cx, cy + r);
        pb.cubic_to(cx - k, cy + r, cx - r, cy + k, cx - r, cy);
        pb.cubic_to(cx - r, cy - k, cx - k, cy - r, cx, cy - r);
        pb.cubic_to(cx + k, cy - r, cx + r, cy - k, cx + r, cy);
    }
    pb.close();
    pb.finish().unwrap()
}

fn rounded_rect(x: f32, y: f32, w: f32, h: f32, r: f32) -> Path {
    // Quarter circles as cubics, the same shape the MoonBit side builds from arcs.
    let k = 0.5522847498307936 * r;
    let (x1, y1) = (x + w, y + h);
    let mut pb = PathBuilder::new();
    pb.move_to(x + r, y);
    pb.line_to(x1 - r, y);
    pb.cubic_to(x1 - r + k, y, x1, y + r - k, x1, y + r);
    pb.line_to(x1, y1 - r);
    pb.cubic_to(x1, y1 - r + k, x1 - r + k, y1, x1 - r, y1);
    pb.line_to(x + r, y1);
    pb.cubic_to(x + r - k, y1, x, y1 - r + k, x, y1 - r);
    pb.line_to(x, y + r);
    pb.cubic_to(x, y + r - k, x + r - k, y, x + r, y);
    pb.close();
    pb.finish().unwrap()
}

/// A pentagram: five corners in order, so every side crosses two others. Filled
/// with the winding rule its middle is solid, with the even-odd rule it is a hole.
fn pentagram(cx: f32, cy: f32, radius: f32) -> Path {
    let mut pb = PathBuilder::new();
    for i in 0..5 {
        let angle = -std::f32::consts::FRAC_PI_2 + i as f32 * 4.0 * std::f32::consts::PI / 5.0;
        let x = cx + radius * angle.cos();
        let y = cy + radius * angle.sin();
        if i == 0 { pb.move_to(x, y); } else { pb.line_to(x, y); }
    }
    pb.close();
    pb.finish().unwrap()
}

fn star(cx: f32, cy: f32, outer: f32, inner: f32) -> Path {
    let mut pb = PathBuilder::new();
    let mut first = true;
    for i in 0..10 {
        let radius = if i % 2 == 0 { outer } else { inner };
        let angle = -std::f32::consts::FRAC_PI_2 + i as f32 * std::f32::consts::PI / 5.0;
        let x = cx + radius * angle.cos();
        let y = cy + radius * angle.sin();
        if first {
            pb.move_to(x, y);
            first = false;
        } else {
            pb.line_to(x, y);
        }
    }
    pb.close();
    pb.finish().unwrap()
}

fn stroke_of(width: f32, cap: LineCap, join: LineJoin, limit: f32) -> Stroke {
    Stroke { width, line_cap: cap, line_join: join, miter_limit: limit, ..Stroke::default() }
}

fn fill_scene() -> Pixmap {
    let mut pixmap = Pixmap::new(SIZE, SIZE).unwrap();
    pixmap.fill_path(
        &pentagram(68.0, 72.0, 52.0),
        &solid(rgba(200, 40, 60, 255)),
        FillRule::Winding,
        Transform::identity(),
        None,
    );
    pixmap.fill_path(
        &pentagram(180.0, 72.0, 52.0),
        &solid(rgba(30, 110, 200, 255)),
        FillRule::EvenOdd,
        Transform::identity(),
        None,
    );
    let mut donut = PathBuilder::new();
    let outer = circle_path(70.0, 180.0, 44.0, false);
    let inner = circle_path(70.0, 180.0, 22.0, true);
    donut.push_path(&outer);
    donut.push_path(&inner);
    pixmap.fill_path(
        &donut.finish().unwrap(),
        &solid(rgba(40, 150, 110, 255)),
        FillRule::Winding,
        Transform::identity(),
        None,
    );
    let mut plate = PathBuilder::new();
    plate.push_path(&rect_path(130.0, 140.0, 100.0, 80.0, false));
    plate.push_path(&rect_path(160.0, 160.0, 40.0, 40.0, true));
    pixmap.fill_path(
        &plate.finish().unwrap(),
        &solid(rgba(240, 180, 40, 255)),
        FillRule::Winding,
        Transform::identity(),
        None,
    );
    pixmap
}

fn stroke_scene() -> Pixmap {
    let mut pixmap = Pixmap::new(SIZE, SIZE).unwrap();
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 40.0);
    pb.line_to(70.0, 20.0);
    pb.line_to(110.0, 60.0);
    pb.line_to(160.0, 25.0);
    pb.line_to(200.0, 70.0);
    pixmap.stroke_path(
        &pb.finish().unwrap(),
        &solid(rgba(60, 60, 70, 255)),
        &stroke_of(12.0, LineCap::Round, LineJoin::Round, 4.0),
        Transform::identity(),
        None,
    );
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 120.0);
    pb.line_to(120.0, 150.0);
    pb.line_to(20.0, 200.0);
    pixmap.stroke_path(
        &pb.finish().unwrap(),
        &solid(rgba(200, 80, 50, 255)),
        &stroke_of(14.0, LineCap::Butt, LineJoin::Miter, 4.0),
        Transform::identity(),
        None,
    );
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 235.0);
    pb.line_to(120.0, 235.0);
    pb.line_to(20.0, 235.5);
    pixmap.stroke_path(
        &pb.finish().unwrap(),
        &solid(rgba(90, 60, 160, 255)),
        &stroke_of(10.0, LineCap::Butt, LineJoin::Miter, 1.5),
        Transform::identity(),
        None,
    );
    let dashed = Stroke {
        width: 8.0,
        line_cap: LineCap::Butt,
        line_join: LineJoin::Round,
        miter_limit: 4.0,
        dash: tiny_skia::StrokeDash::new(vec![14.0, 10.0], 3.0),
    };
    pixmap.stroke_path(
        &circle_path(180.0, 175.0, 44.0, false),
        &solid(rgba(30, 130, 190, 255)),
        &dashed,
        Transform::identity(),
        None,
    );
    pixmap
}

fn gradient_scene() -> Pixmap {
    let mut pixmap = Pixmap::new(SIZE, SIZE).unwrap();
    let stops = vec![
        tiny_skia::GradientStop::new(0.0, rgba(255, 90, 90, 255)),
        tiny_skia::GradientStop::new(0.5, rgba(250, 220, 80, 255)),
        tiny_skia::GradientStop::new(1.0, rgba(60, 140, 240, 255)),
    ];
    let shader = tiny_skia::LinearGradient::new(
        Point::from_xy(16.0, 16.0),
        Point::from_xy(120.0, 120.0),
        stops.clone(),
        SpreadMode::Pad,
        Transform::identity(),
    );
    let mut paint = Paint::default();
    paint.anti_alias = true;
    paint.shader = shader.unwrap();
    pixmap.fill_path(
        &rounded_rect(16.0, 16.0, 104.0, 104.0, 12.0),
        &paint,
        FillRule::Winding,
        Transform::identity(),
        None,
    );
    let radial_stops = vec![
        tiny_skia::GradientStop::new(0.0, rgba(255, 255, 255, 255)),
        tiny_skia::GradientStop::new(1.0, rgba(40, 40, 90, 255)),
    ];
    let shader = tiny_skia::RadialGradient::new(
        Point::from_xy(180.0, 68.0),
        Point::from_xy(180.0, 68.0),
        52.0,
        radial_stops,
        SpreadMode::Pad,
        Transform::identity(),
    );
    let mut paint = Paint::default();
    paint.anti_alias = true;
    paint.shader = shader.unwrap();
    pixmap.fill_path(
        &circle_path(180.0, 68.0, 52.0, false),
        &paint,
        FillRule::Winding,
        Transform::identity(),
        None,
    );
    let repeat_stops = vec![
        tiny_skia::GradientStop::new(0.0, rgba(20, 20, 30, 255)),
        tiny_skia::GradientStop::new(0.5, rgba(90, 190, 220, 255)),
    ];
    let shader = tiny_skia::LinearGradient::new(
        Point::from_xy(16.0, 140.0),
        Point::from_xy(140.0, 140.0),
        repeat_stops,
        SpreadMode::Repeat,
        Transform::identity(),
    );
    let mut paint = Paint::default();
    paint.anti_alias = true;
    paint.shader = shader.unwrap();
    pixmap.fill_path(
        &rounded_rect(16.0, 140.0, 224.0, 100.0, 18.0),
        &paint,
        FillRule::Winding,
        Transform::identity(),
        None,
    );
    pixmap
}

const FONT: &[(char, [u8; 7])] = &[
    (' ', [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000]),
    ('A', [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]),
    ('B', [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110]),
    ('C', [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110]),
    ('F', [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000]),
    ('G', [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111]),
    ('M', [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001]),
    ('N', [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001]),
    ('O', [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]),
    ('X', [0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b01010, 0b10001]),
    ('0', [0b01110, 0b10011, 0b10101, 0b10101, 0b10101, 0b11001, 0b01110]),
    ('1', [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]),
    ('2', [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]),
    ('3', [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110]),
];

fn glyph_path(c: char, x: f32, baseline: f32, cell: f32) -> Option<Path> {
    let rows = FONT.iter().find(|(ch, _)| *ch == c)?.1;
    let mut pb = PathBuilder::new();
    let mut any = false;
    for row in 0..7 {
        for column in 0..5 {
            if (rows[row] >> (4 - column)) & 1 == 0 {
                continue;
            }
            let rx = x + column as f32 * cell;
            let ry = baseline + (row as f32 - 7.0) * cell;
            pb.push_rect(Rect::from_xywh(rx, ry, cell, cell).unwrap());
            any = true;
        }
    }
    if any { pb.finish() } else { None }
}

fn text(pixmap: &mut Pixmap, x: f32, baseline: f32, text: &str, size: f32, color: Color) {
    let cell = size / 8.0;
    let mut pen = x;
    for c in text.chars() {
        if let Some(path) = glyph_path(c, pen, baseline, cell) {
            pixmap.fill_path(
                &path,
                &solid(color),
                FillRule::Winding,
                Transform::identity(),
                None,
            );
        }
        pen += cell * 6.0;
    }
}

fn text_scene() -> Pixmap {
    let mut pixmap = Pixmap::new(SIZE, SIZE).unwrap();
    text(&mut pixmap, 16.0, 64.0, "MOON GFX", 32.0, rgba(20, 20, 30, 255));
    text(&mut pixmap, 16.0, 128.0, "0123 ABC", 16.0, rgba(200, 60, 40, 255));
    text(&mut pixmap, 16.0, 180.0, "NAB", 24.0, rgba(20, 90, 160, 255));
    pixmap
}

fn clip_scene() -> Pixmap {
    let mut pixmap = Pixmap::new(SIZE, SIZE).unwrap();
    let mut mask = tiny_skia::Mask::new(SIZE, SIZE).unwrap();
    mask.fill_path(
        &circle_path(90.0, 100.0, 70.0, false),
        FillRule::Winding,
        true,
        Transform::identity(),
    );
    for i in 0..8 {
        let x = 12.0 + i as f32 * 20.0;
        let color = if i % 2 == 0 {
            rgba(230, 90, 60, 255)
        } else {
            rgba(40, 60, 160, 255)
        };
        pixmap.fill_path(
            &rect_path(x, 10.0, 14.0, 180.0, false),
            &solid(color),
            FillRule::Winding,
            Transform::identity(),
            Some(&mask),
        );
    }
    let mut mask = tiny_skia::Mask::new(SIZE, SIZE).unwrap();
    mask.fill_path(
        &rounded_rect(140.0, 120.0, 100.0, 110.0, 16.0),
        FillRule::Winding,
        true,
        Transform::identity(),
    );
    let stops = vec![
        tiny_skia::GradientStop::new(0.0, rgba(250, 240, 200, 255)),
        tiny_skia::GradientStop::new(1.0, rgba(30, 120, 90, 255)),
    ];
    let shader = tiny_skia::RadialGradient::new(
        Point::from_xy(190.0, 175.0),
        Point::from_xy(190.0, 175.0),
        60.0,
        stops,
        SpreadMode::Pad,
        Transform::identity(),
    );
    let mut paint = Paint::default();
    paint.anti_alias = true;
    paint.shader = shader.unwrap();
    pixmap.fill_path(
        &rect_path(130.0, 110.0, 120.0, 130.0, false),
        &paint,
        FillRule::Winding,
        Transform::identity(),
        Some(&mask),
    );
    pixmap
}

fn curve_scene() -> Pixmap {
    let mut pixmap = Pixmap::new(SIZE, SIZE).unwrap();
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 40.0);
    pb.quad_to(80.0, 0.0, 120.0, 60.0);
    pb.quad_to(160.0, 120.0, 230.0, 60.0);
    pixmap.stroke_path(
        &pb.finish().unwrap(),
        &solid(rgba(180, 60, 140, 255)),
        &stroke_of(10.0, LineCap::Round, LineJoin::Round, 4.0),
        Transform::identity(),
        None,
    );
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 110.0);
    pb.cubic_to(60.0, 80.0, 100.0, 190.0, 140.0, 130.0);
    pb.cubic_to(170.0, 85.0, 210.0, 120.0, 235.0, 105.0);
    pixmap.stroke_path(
        &pb.finish().unwrap(),
        &solid(rgba(40, 120, 180, 255)),
        &stroke_of(8.0, LineCap::Square, LineJoin::Miter, 4.0),
        Transform::identity(),
        None,
    );
    // A blob filled from cubics, with a second one inside drawn the other way.
    let mut blob = PathBuilder::new();
    blob.move_to(60.0, 230.0);
    blob.cubic_to(20.0, 200.0, 40.0, 160.0, 80.0, 175.0);
    blob.cubic_to(110.0, 155.0, 150.0, 175.0, 135.0, 205.0);
    blob.cubic_to(150.0, 235.0, 95.0, 250.0, 60.0, 230.0);
    blob.close();
    pixmap.fill_path(
        &blob.finish().unwrap(),
        &solid(rgba(90, 170, 70, 255)),
        FillRule::Winding,
        Transform::identity(),
        None,
    );
    let mut ring = PathBuilder::new();
    ring.move_to(186.0, 205.0);
    ring.line_to(226.0, 205.0);
    ring.line_to(226.0, 240.0);
    ring.line_to(186.0, 240.0);
    ring.close();
    ring.push_path(&rect_path(196.0, 212.0, 20.0, 21.0, true));
    pixmap.fill_path(
        &ring.finish().unwrap(),
        &solid(rgba(230, 200, 60, 255)),
        FillRule::Winding,
        Transform::identity(),
        None,
    );
    pixmap
}

fn main() {
    let out = std::env::args().nth(1).unwrap_or_else(|| "integration/refs".to_string());
    std::fs::create_dir_all(&out).unwrap();
    let scenes: [(&str, fn() -> Pixmap); 6] = [
        ("fill", fill_scene),
        ("stroke", stroke_scene),
        ("gradient", gradient_scene),
        ("text", text_scene),
        ("clip", clip_scene),
        ("curves", curve_scene),
    ];
    for (name, build) in scenes {
        let pixmap = build();
        let path = format!("{out}/{name}.png");
        pixmap.save_png(&path).unwrap();
        println!("wrote {path}");
    }
}
