// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The backend methods of the software rasteriser.
///
/// Every draw goes through one coverage map, so a clip, a glyph and a filled path
/// composite the same way, and the frame buffer is the only state that survives a
/// call.
pub impl @moongfx.Backend for Surface with fn width(self) {
  self.width
}

///|
pub impl @moongfx.Backend for Surface with fn height(self) {
  self.height
}

///|
pub impl @moongfx.Backend for Surface with fn clear(self, color) {
  let (r, g, b) = color.to_srgb().components()
  let alpha = Float::from_double(color.alpha)
  let pr = premultiply(Float::from_double(r), alpha).round()
  let pg = premultiply(Float::from_double(g), alpha).round()
  let pb = premultiply(Float::from_double(b), alpha).round()
  let pa = (alpha * 255.0).round()
  let bytes : Array[Byte] = Array::make(self.width * self.height * 4, b'\x00')
  for i in 0..<(self.width * self.height) {
    let base = i * 4
    bytes[base] = clamp_byte(pr)
    bytes[base + 1] = clamp_byte(pg)
    bytes[base + 2] = clamp_byte(pb)
    bytes[base + 3] = clamp_byte(pa)
  }
  for i in 0..<self.pixels.length() {
    self.pixels[i] = bytes[i]
  }
}

///|
fn clamp_byte(value : Float) -> Byte {
  let clamped = if value <= 0.0 {
    0
  } else if value >= 255.0 {
    255
  } else {
    value.to_int()
  }
  clamped.to_byte()
}

///|
pub impl @moongfx.Backend for Surface with fn fill_triangles(
  self,
  triangles,
  paint,
) {
  if triangles.length() == 0 {
    return
  }
  let mask = @moongfx.rasterize(triangles, self.width, self.height)
  for y in 0..<self.height {
    for x in 0..<self.width {
      let coverage = mask.coverage(x, y)
      if coverage > 0.0 {
        self.blend(x, y, coverage, paint)
      }
    }
  }
}

///|
pub impl @moongfx.Backend for Surface with fn fill_mask(
  self,
  mask,
  source,
  quad,
  paint,
) {
  self.blend_mask_quad(mask, source, quad, paint, 1.0)
}

///|
pub impl @moongfx.Backend for Surface with fn draw_image(
  self,
  image,
  quad,
  opacity,
) {
  self.blend_image_quad(image, quad, opacity)
}

///|
pub impl @moongfx.Backend for Surface with fn push_clip(self, mask) {
  self.clips.push(mask)
}

///|
pub impl @moongfx.Backend for Surface with fn pop_clip(self) {
  let _ = self.clips.pop()
}

///|
pub impl @moongfx.Backend for Surface with fn flush(self) {
  // Nothing is deferred: every draw has already reached the pixels.
  ignore(self)
}
