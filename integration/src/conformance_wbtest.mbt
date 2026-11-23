// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where the reference images were put, as a path from the workspace root. The CI
/// runs the test from the repository root; a run from inside `integration/` finds
/// them one level down, so both are tried.
let reference_dirs : Array[String] = [
  "integration/refs", "refs", "../integration/refs",
]

///|
/// One scene, as the software backend draws it.
fn draw_scene(name : String) -> @soft.Surface raise {
  match name {
    "fill" => fill_scene()
    "stroke" => stroke_scene()
    "gradient" => gradient_scene()
    "text" => text_scene()
    "clip" => clip_scene()
    "curves" => curve_scene()
    _ => fail("no scene named \{name}")
  }
}

///|
/// The reference image tiny-skia drew for a scene.
fn load_reference(name : String) -> @moonimage.Image raise {
  let mut found : String? = None
  for dir in reference_dirs {
    let path = "\{dir}/\{name}.png"
    if @fs.path_exists(path) {
      found = Some(path)
      break
    }
  }
  let path = match found {
    Some(path) => path
    None => fail("no reference image for \{name} under integration/refs")
  }
  let bytes = @fs.read_file_to_bytes(path)
  @moonimage.decode(bytes)
}

///|
/// How far two images are apart: the mean absolute difference over every channel,
/// the worst single channel difference, and the share of pixels whose worst
/// channel is more than a tenth of the range off.
struct Distance {
  mean : Double
  worst : Double
  far : Double
}

///|
/// The distance between what was drawn and the reference.
///
/// Channels are compared premultiplied. Straight alpha would make a pixel that is
/// nearly clear carry a saturated colour, and two rasterisers that differ by two
/// steps of coverage on such a pixel would look a whole channel apart; premultiplied,
/// they are two steps apart, which is what they are.
fn distance(
  ours : @soft.Surface,
  reference : @moonimage.Image,
) -> Distance raise {
  let width = ours.width()
  let height = ours.height()
  if reference.width.to_int() != width || reference.height.to_int() != height {
    fail(
      "size mismatch: \{width}x\{height} against \{reference.width}x\{reference.height}",
    )
  }
  let mut total : Double = 0.0
  let mut worst : Double = 0.0
  let mut far : Int32 = 0
  let mut counted : Int32 = 0
  for y in 0..<height {
    for x in 0..<width {
      let pixel = reference.pixel(x, y) catch {
        _ => fail("reference pixel out of range")
      }
      let (r, g, b, a) = ours.pixel(x, y)
      let ar = a.to_double()
      let dr = (pixel.r * pixel.a - r.to_double() * ar).abs()
      let dg = (pixel.g * pixel.a - g.to_double() * ar).abs()
      let db = (pixel.b * pixel.a - b.to_double() * ar).abs()
      let da = (pixel.a - ar).abs()
      let top = dr.max(dg).max(db).max(da)
      total = total + dr + dg + db + da
      if top > worst {
        worst = top
      }
      if top > 0.1 {
        far = far + 1
      }
      counted = counted + 1
    }
  }
  {
    mean: total / Int32::to_double(counted * 4),
    worst,
    far: Int32::to_double(far) / Int32::to_double(counted),
  }
}

///|
/// Draw a scene, compare it with its reference, print the numbers and fail when
/// they are outside the tolerance.
///
/// The thresholds allow for the two sides sampling differently: this rasteriser
/// takes eight samples down each pixel row where the reference integrates
/// exactly, and a join is a chain of chords at the stroke's flattening tolerance
/// where the reference draws an arc. A pixel on an edge may therefore differ by a
/// quarter of the range while the picture as a whole has to agree to within a
/// thousandth.
fn check(
  name : String,
  mean_limit~ : Double,
  worst_limit~ : Double,
  far_limit~ : Double,
) -> Unit raise {
  let ours = draw_scene(name)
  let reference = load_reference(name)
  let measured = distance(ours, reference)
  println(
    "\{name}: mean \{measured.mean}, worst \{measured.worst}, far \{measured.far}",
  )
  if measured.mean > mean_limit {
    fail("\{name}: mean difference \{measured.mean} over \{mean_limit}")
  }
  if measured.worst > worst_limit {
    fail("\{name}: worst difference \{measured.worst} over \{worst_limit}")
  }
  if measured.far > far_limit {
    fail("\{name}: \{measured.far} of pixels far off, over \{far_limit}")
  }
}

///|
test "fill agrees with the reference" {
  check("fill", mean_limit=0.002, worst_limit=0.8, far_limit=0.01)
}

///|
test "stroke agrees with the reference" {
  check("stroke", mean_limit=0.002, worst_limit=0.8, far_limit=0.01)
}

///|
test "gradient agrees with the reference" {
  check("gradient", mean_limit=0.002, worst_limit=0.8, far_limit=0.01)
}

///|
test "text agrees with the reference" {
  check("text", mean_limit=0.001, worst_limit=0.05, far_limit=0.0)
}

///|
test "clip agrees with the reference" {
  check("clip", mean_limit=0.002, worst_limit=0.8, far_limit=0.01)
}

///|
test "curves agree with the reference" {
  check("curves", mean_limit=0.002, worst_limit=0.8, far_limit=0.01)
}
