// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The point type vertices are written in, re-exported from moonmath.
pub using @moonmath {type Vec2}

///|
/// One vertex of a batch: where it lands on the target, and where it samples.
///
/// `texcoord` is in the pixel space of the texture the draw call names, so an
/// atlas cell is `(x, y)` to `(x + width, y + height)`. A plain fill leaves it at
/// zero and the backend ignores it.
#derive(Debug, Eq)
pub(all) struct Vertex {
  position : Vec2
  texcoord : Vec2
}

///|
/// The texture a draw call samples, if any.
///
/// A layer names a texture the backend has uploaded: an atlas of glyph coverage,
/// a clip mask, or a photograph. Coverage multiplies the paint's alpha; colour
/// replaces it. Keeping the two apart is what lets one atlas serve both a
/// monochrome clip and a glyph.
#derive(Debug, Eq)
pub(all) enum Texture {
  None
  /// An eight-bit coverage mask: red carries the coverage.
  Coverage(Int32)
  /// An RGBA image.
  Colour(Int32)
}

///|
/// One draw call: a range of the index buffer, the paint behind it, the texture
/// it samples, and the clip in force when it was recorded.
#derive(Debug)
pub(all) struct DrawCall {
  first : Int32
  count : Int32
  paint : @moongfx.Paint
  texture : Texture
  clip : Int32
}

///|
/// Everything one frame needs: vertices, indices and the calls that use them.
///
/// The index buffer is a triangle list in device space, wound clockwise, which is
/// the winding a backend culls back faces by. Clips are indices into the clip
/// masks the backend holds, not geometry: a clip in this library is coverage, and
/// a backend multiplies it in, exactly as the software one does per pixel.
#derive(Debug)
pub(all) struct Batch {
  vertices : Array[Vertex]
  indices : Array[Int32]
  draws : Array[DrawCall]
}

///|
/// An empty batch.
pub fn Batch::new() -> Batch {
  { vertices: [], indices: [], draws: [], }
}

///|
/// How many triangles the batch holds.
pub fn Batch::triangle_count(self : Batch) -> Int32 {
  self.indices.length() / 3
}

///|
/// How many draw calls the batch holds.
pub fn Batch::draw_count(self : Batch) -> Int32 {
  self.draws.length()
}

///|
/// Whether there is nothing to draw.
pub fn Batch::is_empty(self : Batch) -> Bool {
  self.indices.length() == 0
}

///|
/// A batch under construction.
pub struct BatchBuilder {
  vertices : Array[Vertex]
  indices : Array[Int32]
  draws : Array[DrawCall]
  mut clip : Int32
}

///|
/// A builder with no clip.
pub fn BatchBuilder::new() -> BatchBuilder {
  { vertices: [], indices: [], draws: [], clip: 0, }
}

///|
/// Record the clip every following draw call uses.
pub fn BatchBuilder::set_clip(self : BatchBuilder, clip : Int32) -> Unit {
  self.clip = clip
}

///|
/// Add triangles painted with one paint, as a single draw call.
pub fn BatchBuilder::fill(
  self : BatchBuilder,
  triangles : Array[@moongfx.Triangle],
  paint : @moongfx.Paint,
) -> Unit {
  if triangles.length() == 0 {
    return
  }
  let first = self.indices.length()
  for triangle in triangles {
    let base = self.vertices.length()
    self.vertices.push({ position: triangle.a, texcoord: Vec2::zero(), })
    self.vertices.push({ position: triangle.b, texcoord: Vec2::zero(), })
    self.vertices.push({ position: triangle.c, texcoord: Vec2::zero(), })
    self.indices.push(base)
    self.indices.push(base + 1)
    self.indices.push(base + 2)
  }
  self.draws.push({
    first,
    count: self.indices.length() - first,
    paint,
    texture: None,
    clip: self.clip,
  })
}

///|
/// Add a quad that samples `source` of a coverage texture, painted with `paint`.
///
/// This is how a glyph reaches the screen: one quad, one draw call, the atlas
/// bound as the coverage texture.
pub fn BatchBuilder::mask_quad(
  self : BatchBuilder,
  source : @moongfx.Bounds,
  quad : @moongfx.Quad,
  paint : @moongfx.Paint,
  layer : Int32,
) -> Unit {
  let first = self.indices.length()
  self.quad(quad, source)
  self.draws.push({
    first,
    count: 6,
    paint,
    texture: Coverage(layer),
    clip: self.clip,
  })
}

///|
/// Add a quad that samples an entire image in `layer`.
pub fn BatchBuilder::image_quad(
  self : BatchBuilder,
  quad : @moongfx.Quad,
  width : Int32,
  height : Int32,
  layer : Int32,
) -> Unit {
  let first = self.indices.length()
  let source : @moongfx.Bounds = {
    min_x: 0.0,
    min_y: 0.0,
    max_x: Float::from_double(Int32::to_double(width)),
    max_y: Float::from_double(Int32::to_double(height)),
  }
  self.quad(quad, source)
  self.draws.push({
    first,
    count: 6,
    paint: @moongfx.solid(@moonrgba.Color::white()),
    texture: Colour(layer),
    clip: self.clip,
  })
}

///|
/// Four vertices and two triangles: the quad geometry both masked and image draws
/// use.
fn BatchBuilder::quad(
  self : BatchBuilder,
  quad : @moongfx.Quad,
  source : @moongfx.Bounds,
) -> Unit {
  let base = self.vertices.length()
  self.vertices.push({
    position: quad.top_left,
    texcoord: Vec2::new(source.min_x, source.min_y),
  })
  self.vertices.push({
    position: quad.top_right,
    texcoord: Vec2::new(source.max_x, source.min_y),
  })
  self.vertices.push({
    position: quad.bottom_right,
    texcoord: Vec2::new(source.max_x, source.max_y),
  })
  self.vertices.push({
    position: quad.bottom_left,
    texcoord: Vec2::new(source.min_x, source.max_y),
  })
  self.indices.push(base)
  self.indices.push(base + 1)
  self.indices.push(base + 2)
  self.indices.push(base)
  self.indices.push(base + 2)
  self.indices.push(base + 3)
}

///|
/// The batch so far.
pub fn BatchBuilder::build(self : BatchBuilder) -> Batch {
  { vertices: self.vertices, indices: self.indices, draws: self.draws, }
}
