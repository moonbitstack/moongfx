// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A frame buffer that a canvas draws into.
///
/// Pixels are held premultiplied, which makes compositing one multiply and one
/// add per pixel and keeps a half-covered edge from brightening what is under it.
/// `to_image` unpremultiplies on the way out, because that is the straight-alpha
/// form every file format wants.
pub struct Surface {
  width : Int32
  height : Int32
  /// Red, green, blue, alpha, each premultiplied, four bytes a pixel.
  pixels : Array[Byte]
  clips : Array[@moongfx.Mask]
}

///|
/// A transparent surface of the given size.
pub fn Surface::new(width : Int32, height : Int32) -> Surface {
  let width = if width < 0 { 0 } else { width }
  let height = if height < 0 { 0 } else { height }
  {
    width,
    height,
    pixels: Array::make(width * height * 4, b'\x00'),
    clips: [],
  }
}

///|
/// The width in pixels.
pub fn Surface::width(self : Surface) -> Int32 {
  self.width
}

///|
/// The height in pixels.
pub fn Surface::height(self : Surface) -> Int32 {
  self.height
}

///|
/// One pixel as straight sRGB channels and alpha, each from zero to one.
pub fn Surface::pixel(
  self : Surface,
  x : Int32,
  y : Int32,
) -> (Float, Float, Float, Float) {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    return (0.0, 0.0, 0.0, 0.0)
  }
  let base = (y * self.width + x) * 4
  let alpha = self.pixels[base + 3]
  if alpha == 0 {
    return (0.0, 0.0, 0.0, 0.0)
  }
  let a = Float::from_double(alpha.to_double() / 255.0)
  let r = Float::from_double(self.pixels[base].to_double() / 255.0) / a
  let g = Float::from_double(self.pixels[base + 1].to_double() / 255.0) / a
  let b = Float::from_double(self.pixels[base + 2].to_double() / 255.0) / a
  (r, g, b, a)
}

///|
/// The frame buffer as an image with straight alpha, ready to encode.
pub fn Surface::to_image(self : Surface) -> @moonimage.Image {
  let bytes : Array[Byte] = Array::make(self.width * self.height * 4, b'\x00')
  for i in 0..<(self.width * self.height) {
    let base = i * 4
    let alpha = self.pixels[base + 3].to_int()
    if alpha == 0 {
      continue
    }
    bytes[base] = unpremultiply(self.pixels[base].to_int(), alpha)
    bytes[base + 1] = unpremultiply(self.pixels[base + 1].to_int(), alpha)
    bytes[base + 2] = unpremultiply(self.pixels[base + 2].to_int(), alpha)
    bytes[base + 3] = self.pixels[base + 3]
  }
  let encoded = Bytes::from_array(bytes)
  @moonimage.Image::of(
    self.width,
    self.height,
    @moonimage.PixelFormat::Rgba8,
    encoded,
    premultiplied=false,
  ) catch {
    _ =>
      @moonimage.Image::new(
        self.width,
        self.height,
        @moonimage.PixelFormat::Rgba8,
        premultiplied=false,
      )
  }
}

///|
fn unpremultiply(value : Int32, alpha : Int32) -> Byte {
  let scaled = (value * 255 + alpha / 2) / alpha
  let clamped = if scaled > 255 { 255 } else if scaled < 0 { 0 } else { scaled }
  clamped.to_byte()
}

///|
/// A straight channel and an alpha as one premultiplied byte.
fn premultiply(channel : Float, alpha : Float) -> Float {
  channel * alpha * 255.0
}

///|
/// The coverage the clip stack allows at a pixel, from zero to one.
fn Surface::clip_at(self : Surface, x : Int32, y : Int32) -> Float {
  match self.clips.last() {
    None => 1.0
    Some(mask) => mask.coverage(x, y)
  }
}

///|
/// Put one source pixel over the frame buffer at `x`, `y`, scaled by `coverage`.
fn Surface::blend(
  self : Surface,
  x : Int32,
  y : Int32,
  coverage : Float,
  paint : @moongfx.Paint,
) -> Unit {
  if coverage <= 0.0 || x < 0 || y < 0 || x >= self.width || y >= self.height {
    return
  }
  let allowed = coverage * self.clip_at(x, y)
  if allowed <= 0.0 {
    return
  }
  let point = @moonmath.Vec2::new(
    Float::from_double(Int32::to_double(x) + 0.5),
    Float::from_double(Int32::to_double(y) + 0.5),
  )
  let (r, g, b, a) = paint.sample(point)
  let alpha = a * allowed
  if alpha <= 0.0 {
    return
  }
  let base = (y * self.width + x) * 4
  let inverse : Float = 1.0 - alpha
  self.pixels[base] = over(self.pixels[base], premultiply(r, alpha), inverse)
  self.pixels[base + 1] = over(
    self.pixels[base + 1],
    premultiply(g, alpha),
    inverse,
  )
  self.pixels[base + 2] = over(
    self.pixels[base + 2],
    premultiply(b, alpha),
    inverse,
  )
  self.pixels[base + 3] = over(self.pixels[base + 3], alpha * 255.0, inverse)
}

///|
/// Destination scaled back by how much the source covers, plus the source.
fn over(destination : Byte, source : Float, inverse : Float) -> Byte {
  let value = Float::from_double(destination.to_double()) * inverse + source
  let rounded = value.round()
  let clamped = if rounded <= 0.0 {
    0
  } else if rounded >= 255.0 {
    255
  } else {
    rounded.to_int()
  }
  clamped.to_byte()
}

///|
/// The affine that maps the unit square onto `quad`, whose corners run clockwise
/// from the top left.
fn quad_affine(quad : @moongfx.Quad) -> @moonmath.Affine2? {
  let ux = quad.top_right.x - quad.top_left.x
  let uy = quad.top_right.y - quad.top_left.y
  let vx = quad.bottom_left.x - quad.top_left.x
  let vy = quad.bottom_left.y - quad.top_left.y
  if (ux * vy - uy * vx).abs() <= 1.0e-12 {
    return None
  }
  Some(
    @moonmath.Affine2::new(
      @moonmath.Mat2::from_cols(
        @moonmath.Vec2::new(ux, uy),
        @moonmath.Vec2::new(vx, vy),
      ),
      quad.top_left,
    ),
  )
}

///|
/// The pixels a quad can touch, clamped to the surface.
fn Surface::quad_region(
  self : Surface,
  quad : @moongfx.Quad,
) -> (Int32, Int32, Int32, Int32) {
  let box = quad.bounds()
  let x_start = if box.min_x < 0.0 { 0 } else { box.min_x.floor().to_int() }
  let y_start = if box.min_y < 0.0 { 0 } else { box.min_y.floor().to_int() }
  let x_end = if box.max_x > Float::from_double(Int32::to_double(self.width)) {
    self.width
  } else {
    box.max_x.ceil().to_int()
  }
  let y_end = if box.max_y > Float::from_double(Int32::to_double(self.height)) {
    self.height
  } else {
    box.max_y.ceil().to_int()
  }
  (x_start, y_start, x_end, y_end)
}

///|
/// Draw a mask through a quad, tinted by a paint.
fn Surface::blend_mask_quad(
  self : Surface,
  mask : @moongfx.Mask,
  source : @moongfx.Bounds,
  quad : @moongfx.Quad,
  paint : @moongfx.Paint,
  opacity : Float,
) -> Unit {
  let affine = match quad_affine(quad) {
    Some(affine) => affine
    None => return
  }
  let inverse = match affine.inverse() {
    Some(inverse) => inverse
    None => return
  }
  let (x_start, y_start, x_end, y_end) = self.quad_region(quad)
  for y in y_start..<y_end {
    for x in x_start..<x_end {
      let centre = @moonmath.Vec2::new(
        Float::from_double(Int32::to_double(x) + 0.5),
        Float::from_double(Int32::to_double(y) + 0.5),
      )
      let unit = inverse.transform_point(centre)
      if unit.x < 0.0 || unit.y < 0.0 || unit.x > 1.0 || unit.y > 1.0 {
        continue
      }
      let coverage = sample_mask(
        mask,
        source.min_x + unit.x * source.width(),
        source.min_y + unit.y * source.height(),
      )
      self.blend(x, y, coverage * opacity, paint)
    }
  }
}

///|
/// A bilinear sample of a mask at a point in its own pixel space, with the edge
/// clamped.
fn sample_mask(mask : @moongfx.Mask, x : Float, y : Float) -> Float {
  if mask.width() == 0 || mask.height() == 0 {
    return 0.0
  }
  let fx = x - 0.5
  let fy = y - 0.5
  let x0 = fx.floor()
  let y0 = fy.floor()
  let dx = fx - x0
  let dy = fy - y0
  let ix = x0.to_int()
  let iy = y0.to_int()
  let c00 = mask.coverage(ix, iy)
  let c10 = mask.coverage(ix + 1, iy)
  let c01 = mask.coverage(ix, iy + 1)
  let c11 = mask.coverage(ix + 1, iy + 1)
  c00 * (1.0 - dx) * (1.0 - dy) +
  c10 * dx * (1.0 - dy) +
  c01 * (1.0 - dx) * dy +
  c11 * dx * dy
}

///|
/// Draw an image through a quad, with opacity.
fn Surface::blend_image_quad(
  self : Surface,
  image : @moonimage.Image,
  quad : @moongfx.Quad,
  opacity : Float,
) -> Unit {
  let affine = match quad_affine(quad) {
    Some(affine) => affine
    None => return
  }
  let inverse = match affine.inverse() {
    Some(inverse) => inverse
    None => return
  }
  let (x_start, y_start, x_end, y_end) = self.quad_region(quad)
  let width = Float::from_double(image.width.to_double())
  let height = Float::from_double(image.height.to_double())
  for y in y_start..<y_end {
    for x in x_start..<x_end {
      let centre = @moonmath.Vec2::new(
        Float::from_double(Int32::to_double(x) + 0.5),
        Float::from_double(Int32::to_double(y) + 0.5),
      )
      let unit = inverse.transform_point(centre)
      if unit.x < 0.0 || unit.y < 0.0 || unit.x > 1.0 || unit.y > 1.0 {
        continue
      }
      let texel = sample_image(image, unit.x * width, unit.y * height)
      let coverage = texel.3 * opacity
      if coverage <= 0.0 {
        continue
      }
      self.blend_colour(x, y, coverage, texel.0, texel.1, texel.2)
    }
  }
}

///|
/// Put a colour over the frame buffer at `x`, `y`, with the given coverage, the
/// way `blend` does for a paint.
fn Surface::blend_colour(
  self : Surface,
  x : Int32,
  y : Int32,
  coverage : Float,
  r : Float,
  g : Float,
  b : Float,
) -> Unit {
  let allowed = coverage * self.clip_at(x, y)
  if allowed <= 0.0 {
    return
  }
  let base = (y * self.width + x) * 4
  let inverse : Float = 1.0 - allowed
  self.pixels[base] = over(self.pixels[base], premultiply(r, allowed), inverse)
  self.pixels[base + 1] = over(
    self.pixels[base + 1],
    premultiply(g, allowed),
    inverse,
  )
  self.pixels[base + 2] = over(
    self.pixels[base + 2],
    premultiply(b, allowed),
    inverse,
  )
  self.pixels[base + 3] = over(self.pixels[base + 3], allowed * 255.0, inverse)
}

///|
/// One texel of an image as straight sRGB, clamped at the edges.
fn sample_image(
  image : @moonimage.Image,
  x : Float,
  y : Float,
) -> (Float, Float, Float, Float) {
  let width = image.width.to_int()
  let height = image.height.to_int()
  if width <= 0 || height <= 0 {
    return (0.0, 0.0, 0.0, 0.0)
  }
  let fx = x - 0.5
  let fy = y - 0.5
  let x0 = fx.floor()
  let y0 = fy.floor()
  let dx = fx - x0
  let dy = fy - y0
  let ix = x0.to_int()
  let iy = y0.to_int()
  let c00 = texel(image, ix, iy)
  let c10 = texel(image, ix + 1, iy)
  let c01 = texel(image, ix, iy + 1)
  let c11 = texel(image, ix + 1, iy + 1)
  (
    c00.0 * (1.0 - dx) * (1.0 - dy) +
    c10.0 * dx * (1.0 - dy) +
    c01.0 * (1.0 - dx) * dy +
    c11.0 * dx * dy,
    c00.1 * (1.0 - dx) * (1.0 - dy) +
    c10.1 * dx * (1.0 - dy) +
    c01.1 * (1.0 - dx) * dy +
    c11.1 * dx * dy,
    c00.2 * (1.0 - dx) * (1.0 - dy) +
    c10.2 * dx * (1.0 - dy) +
    c01.2 * (1.0 - dx) * dy +
    c11.2 * dx * dy,
    c00.3 * (1.0 - dx) * (1.0 - dy) +
    c10.3 * dx * (1.0 - dy) +
    c01.3 * (1.0 - dx) * dy +
    c11.3 * dx * dy,
  )
}

///|
fn texel(
  image : @moonimage.Image,
  x : Int32,
  y : Int32,
) -> (Float, Float, Float, Float) {
  let width = image.width.to_int()
  let height = image.height.to_int()
  let cx = if x < 0 { 0 } else if x >= width { width - 1 } else { x }
  let cy = if y < 0 { 0 } else if y >= height { height - 1 } else { y }
  let pixel = image.pixel(cx, cy) catch { _ => return (0.0, 0.0, 0.0, 0.0) }
  (
    Float::from_double(pixel.r),
    Float::from_double(pixel.g),
    Float::from_double(pixel.b),
    Float::from_double(pixel.a),
  )
}
