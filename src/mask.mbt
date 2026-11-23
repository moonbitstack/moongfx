// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How many times each pixel row is sampled from top to bottom. Eight keeps a
/// shallow edge within a sixteenth of a pixel of the exact area, which is finer
/// than an 8-bit channel can show.
let subsamples : Int32 = 8

///|
/// An eight-bit coverage map: how much of each pixel a shape covers, from zero to
/// 255.
///
/// The same type serves as a clip region and as a glyph's rasterised outline, so
/// a backend has one thing to learn.
#derive(Debug, Eq)
pub(all) struct Mask {
  width : Int32
  height : Int32
  /// One byte a pixel, row by row from the top.
  data : Array[Byte]
}

///|
/// An empty mask.
pub fn Mask::new(width : Int32, height : Int32) -> Mask {
  let size = if width > 0 && height > 0 { width * height } else { 0 }
  { width, height, data: Array::make(size, 0), }
}

///|
/// The mask's width in pixels.
pub fn Mask::width(self : Mask) -> Int32 {
  self.width
}

///|
/// The mask's height in pixels.
pub fn Mask::height(self : Mask) -> Int32 {
  self.height
}

///|
/// The coverage at a pixel, 0 to 255.
pub fn Mask::at(self : Mask, x : Int32, y : Int32) -> Int32 {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    return 0
  }
  self.data[y * self.width + x].to_int()
}

///|
/// The coverage at a pixel, from zero to one.
pub fn Mask::coverage(self : Mask, x : Int32, y : Int32) -> Float {
  as_float(self.at(x, y)) / 255.0
}

///|
/// Set one pixel's coverage, clamped to the byte range.
pub fn Mask::set(self : Mask, x : Int32, y : Int32, value : Int32) -> Unit {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    return
  }
  let clamped = if value < 0 { 0 } else if value > 255 { 255 } else { value }
  self.data[y * self.width + x] = clamped.to_byte()
}

///|
/// The mask that covers only where both masks do, which is how a clip stack
/// narrows.
pub fn Mask::intersect(self : Mask, other : Mask) -> Mask {
  let out = Mask::new(self.width, self.height)
  if other.width != self.width || other.height != self.height {
    return out
  }
  for i in 0..<self.data.length() {
    let product = self.data[i].to_int() * other.data[i].to_int()
    out.data[i] = ((product + 127) / 255).to_byte()
  }
  out
}

///|
/// How much of the segment from `(x0, y0)` to `(x1, y1)` covers each pixel of one
/// row, added into `row`.
///
/// The ends are fractional, so a span that starts or stops part way through a
/// pixel adds exactly its share; this is what makes horizontal edges as smooth as
/// vertical ones.
fn add_span(row : Array[Float], x0 : Float, x1 : Float, width : Int32) -> Unit {
  let mut left = x0
  let mut right = x1
  if right <= 0.0 || left >= as_float(width) || right <= left {
    return
  }
  if left < 0.0 {
    left = 0.0
  }
  if right > as_float(width) {
    right = as_float(width)
  }
  let first = left.floor().to_int()
  let last = right.floor().to_int()
  if first == last {
    if first < width {
      row[first] = row[first] + (right - left)
    }
    return
  }
  if first < width {
    row[first] = row[first] + (as_float(first + 1) - left)
  }
  for i in (first + 1)..<last {
    if i < width {
      row[i] = row[i] + 1.0
    }
  }
  if last < width {
    row[last] = row[last] + (right - as_float(last))
  }
}

///|
/// One row of one triangle: the left and right crossing at `y`, or nothing when
/// the scanline misses.
fn span_at(a : Vec2, b : Vec2, c : Vec2, y : Float) -> (Float, Float)? {
  let mut low : Float = 0.0
  let mut high : Float = 0.0
  let mut found = 0
  let edges = [(a, b), (b, c), (c, a)]
  for pair in edges {
    let (p, q) = pair
    if (p.y <= y) != (q.y <= y) {
      let dy = q.y - p.y
      let x = p.x + (y - p.y) * (q.x - p.x) / dy
      if found == 0 {
        low = x
        high = x
      } else {
        if x < low {
          low = x
        }
        if x > high {
          high = x
        }
      }
      found = found + 1
    }
  }
  if found < 2 {
    None
  } else {
    Some((low, high))
  }
}

///|
/// The coverage of `triangles` over a `width` by `height` target.
///
/// Triangles that meet along an edge add up to full coverage rather than
/// overshooting, and triangles that overlap saturate, so a tessellation that
/// touches itself — a stroke's joins, say — inks its area once.
pub fn rasterize(
  triangles : Array[Triangle],
  width : Int32,
  height : Int32,
) -> Mask {
  let mask = Mask::new(width, height)
  if width <= 0 || height <= 0 || triangles.length() == 0 {
    return mask
  }
  let row : Array[Float] = Array::make(width, 0.0)
  let scale : Float = 1.0 / as_float(subsamples)
  for triangle in triangles {
    let box = triangle.bounds()
    let y_start = if box.min_y < 0.0 { 0 } else { box.min_y.floor().to_int() }
    let y_end = if box.max_y > as_float(height) {
      height
    } else {
      box.max_y.ceil().to_int()
    }
    let x_start = if box.min_x < 0.0 { 0 } else { box.min_x.floor().to_int() }
    let x_end = if box.max_x > as_float(width) {
      width
    } else {
      box.max_x.ceil().to_int() + 1
    }
    let x_end = if x_end > width { width } else { x_end }
    if y_start >= y_end || x_start >= x_end {
      continue
    }
    for py in y_start..<y_end {
      for x in x_start..<x_end {
        row[x] = 0.0
      }
      let mut any = false
      for s in 0..<subsamples {
        let y = as_float(py) + (as_float(s) + 0.5) * scale
        match span_at(triangle.a, triangle.b, triangle.c, y) {
          Some(span) => {
            add_span(row, span.0, span.1, width)
            any = true
          }
          None => ()
        }
      }
      if !any {
        continue
      }
      let base = py * width
      for x in x_start..<x_end {
        let add = row[x] * scale
        if add > 0.0 {
          mask.data[base + x] = saturating_add(mask.data[base + x], add)
        }
      }
    }
  }
  mask
}

///|
/// A byte plus a coverage, rounded and clamped at 255.
fn saturating_add(value : Byte, coverage : Float) -> Byte {
  let sum = as_float(value.to_int()) + (coverage * 255.0).round()
  let clamped = if sum <= 0.0 {
    0
  } else if sum >= 255.0 {
    255
  } else {
    sum.to_int()
  }
  clamped.to_byte()
}
