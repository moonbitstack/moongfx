//! Draws three of the reference scenes with raqote, a rasteriser unrelated to
//! tiny-skia, and writes them as PNG.
//!
//! Two independent implementations agreeing with this library is worth more than
//! one agreeing twice, so the conformance test compares against both. Run from
//! the repository root: `cargo run --release --bin raqote_refs -- integration/refs-raqote`.

use raqote::{DrawTarget, LineCap, LineJoin, PathBuilder, SolidSource, Source, StrokeStyle, Winding};

const SIZE: i32 = 256;

fn solid(r: u8, g: u8, b: u8, a: u8) -> Source {
    Source::Solid(SolidSource { r, g, b, a })
}

fn stroke_of(width: f32, cap: LineCap, join: LineJoin, limit: f32) -> StrokeStyle {
    StrokeStyle {
        cap,
        join,
        mitre_limit: limit,
        width,
        dash_array: Vec::new(),
        dash_offset: 0.0,
    }
}

fn circle_into(pb: &mut PathBuilder, cx: f32, cy: f32, r: f32) {
    let k = 0.5522847498307936 * r;
    pb.move_to(cx + r, cy);
    pb.cubic_to(cx + r, cy + k, cx + k, cy + r, cx, cy + r);
    pb.cubic_to(cx - k, cy + r, cx - r, cy + k, cx - r, cy);
    pb.cubic_to(cx - r, cy - k, cx - k, cy - r, cx, cy - r);
    pb.cubic_to(cx + k, cy - r, cx + r, cy - k, cx + r, cy);
    pb.close();
}

fn stroke_scene(dt: &mut DrawTarget) {
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 40.0);
    pb.line_to(70.0, 20.0);
    pb.line_to(110.0, 60.0);
    pb.line_to(160.0, 25.0);
    pb.line_to(200.0, 70.0);
    let mut style = stroke_of(12.0, LineCap::Round, LineJoin::Round, 4.0);
    dt.stroke(&pb.finish(), &style, &solid(60, 60, 70, 255));
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 120.0);
    pb.line_to(120.0, 150.0);
    pb.line_to(20.0, 200.0);
    style = stroke_of(14.0, LineCap::Butt, LineJoin::Mitre, 4.0);
    dt.stroke(&pb.finish(), &style, &solid(200, 80, 50, 255));
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 235.0);
    pb.line_to(120.0, 235.0);
    pb.line_to(20.0, 235.5);
    style = stroke_of(10.0, LineCap::Butt, LineJoin::Mitre, 1.5);
    dt.stroke(&pb.finish(), &style, &solid(90, 60, 160, 255));
    let mut style = stroke_of(8.0, LineCap::Butt, LineJoin::Round, 4.0);
    style.dash_array = vec![14.0, 10.0];
    style.dash_offset = 3.0;
    let mut dashed = PathBuilder::new();
    circle_into(&mut dashed, 180.0, 175.0, 44.0);
    dt.stroke(&dashed.finish(), &style, &solid(30, 130, 190, 255));
}

fn curve_scene(dt: &mut DrawTarget) {
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 40.0);
    pb.quad_to(80.0, 0.0, 120.0, 60.0);
    pb.quad_to(160.0, 120.0, 230.0, 60.0);
    dt.stroke(
        &pb.finish(),
        &stroke_of(10.0, LineCap::Round, LineJoin::Round, 4.0),
        &solid(180, 60, 140, 255),
    );
    let mut pb = PathBuilder::new();
    pb.move_to(20.0, 110.0);
    pb.cubic_to(60.0, 80.0, 100.0, 190.0, 140.0, 130.0);
    pb.cubic_to(170.0, 85.0, 210.0, 120.0, 235.0, 105.0);
    dt.stroke(
        &pb.finish(),
        &stroke_of(8.0, LineCap::Square, LineJoin::Mitre, 4.0),
        &solid(40, 120, 180, 255),
    );
    let mut blob = PathBuilder::new();
    blob.move_to(60.0, 230.0);
    blob.cubic_to(20.0, 200.0, 40.0, 160.0, 80.0, 175.0);
    blob.cubic_to(110.0, 155.0, 150.0, 175.0, 135.0, 205.0);
    blob.cubic_to(150.0, 235.0, 95.0, 250.0, 60.0, 230.0);
    blob.close();
    dt.fill(&blob.finish(), &solid(90, 170, 70, 255), Winding::NonZero);
    let mut ring = PathBuilder::new();
    ring.move_to(186.0, 205.0);
    ring.line_to(226.0, 205.0);
    ring.line_to(226.0, 240.0);
    ring.line_to(186.0, 240.0);
    ring.close();
    ring.move_to(196.0, 212.0);
    ring.line_to(196.0, 233.0);
    ring.line_to(216.0, 233.0);
    ring.line_to(216.0, 212.0);
    ring.close();
    dt.fill(&ring.finish(), &solid(230, 200, 60, 255), Winding::NonZero);
}

/// Write a draw target as a PNG with straight alpha, the form the comparison reads.
fn save(dt: &DrawTarget, path: &str) {
    let mut pixels = Vec::with_capacity((SIZE * SIZE * 4) as usize);
    for word in dt.get_data() {
        let a = (word >> 24) & 0xff;
        let r = (word >> 16) & 0xff;
        let g = (word >> 8) & 0xff;
        let b = word & 0xff;
        if a == 0 {
            pixels.extend_from_slice(&[0, 0, 0, 0]);
            continue;
        }
        let unpremultiply = |c: u32| ((c * 255 + a / 2) / a).min(255) as u8;
        pixels.extend_from_slice(&[unpremultiply(r), unpremultiply(g), unpremultiply(b), a as u8]);
    }
    let file = std::fs::File::create(path).unwrap();
    let mut encoder = png::Encoder::new(std::io::BufWriter::new(file), SIZE as u32, SIZE as u32);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().unwrap();
    writer.write_image_data(&pixels).unwrap();
}

fn main() {
    let out = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "integration/refs-raqote".to_string());
    std::fs::create_dir_all(&out).unwrap();
    let scenes: [(&str, fn(&mut DrawTarget)); 2] = [
        ("stroke", stroke_scene),
        ("curves", curve_scene),
    ];
    for (name, build) in scenes {
        let mut dt = DrawTarget::new(SIZE, SIZE);
        build(&mut dt);
        let path = format!("{out}/{name}.png");
        save(&dt, &path);
        println!("wrote {path}");
    }
}
