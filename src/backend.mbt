// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where a mask or an image lands on the target: four corners in device space,
/// clockwise from the top left, each the corner the name says.
///
/// The quad is what lets a glyph, a rasterised clip or a photograph be drawn
/// through any affine transform without the backend knowing about transforms.
#derive(Debug, Eq)
pub(all) struct Quad {
  top_left : Vec2
  top_right : Vec2
  bottom_right : Vec2
  bottom_left : Vec2
}

///|
/// The quad covering a box, corners in its own order.
pub fn Quad::of_bounds(box : Bounds) -> Quad {
  {
    top_left: Vec2::new(box.min_x, box.min_y),
    top_right: Vec2::new(box.max_x, box.min_y),
    bottom_right: Vec2::new(box.max_x, box.max_y),
    bottom_left: Vec2::new(box.min_x, box.max_y),
  }
}

///|
/// The quad through an affine transform.
pub fn Quad::map(self : Quad, affine : Affine2) -> Quad {
  {
    top_left: affine.transform_point(self.top_left),
    top_right: affine.transform_point(self.top_right),
    bottom_right: affine.transform_point(self.bottom_right),
    bottom_left: affine.transform_point(self.bottom_left),
  }
}

///|
/// The box the four corners span.
pub fn Quad::bounds(self : Quad) -> Bounds {
  Bounds::nothing()
  .add_point(self.top_left)
  .add_point(self.top_right)
  .add_point(self.bottom_right)
  .add_point(self.bottom_left)
}

///|
/// The thing a canvas draws into.
///
/// A backend only ever sees geometry in device space — triangles already
/// tessellated, masks already rasterised, paints already moved — so the work a
/// backend has to do is shading and compositing, and swapping one backend for
/// another cannot change what a caller wrote.
///
/// Coverage arrives as a mask because that is the one representation both a
/// software rasteriser and a GPU can produce and consume: the software one
/// computes it, the GPU one samples it from a texture of the clip or the glyph.
pub(open) trait Backend {
  /// The width of the target in pixels.
  fn width(Self) -> Int32
  /// The height of the target in pixels.
  fn height(Self) -> Int32
  /// Fill the whole target with one colour, replacing what was there.
  fn clear(Self, @moonrgba.Color) -> Unit
  /// Draw triangles, antialiased, painted by `paint`.
  fn fill_triangles(Self, Array[Triangle], Paint) -> Unit
  /// Draw the `source` part of a mask through a quad, tinted by `paint`.
  ///
  /// The source rectangle is what lets one atlas texture serve every glyph: the
  /// quad says where the glyph goes, the source says which cell of the atlas it
  /// is. A whole-surface mask, such as a clip, passes its own extent.
  fn fill_mask(Self, Mask, Bounds, Quad, Paint) -> Unit
  /// Draw an image through a quad, scaled by `opacity`.
  fn draw_image(Self, @moonimage.Image, Quad, Float) -> Unit
  /// Narrow what later draws may touch to `mask`, which covers the whole target.
  fn push_clip(Self, Mask) -> Unit
  /// Undo the last `push_clip`.
  fn pop_clip(Self) -> Unit
  /// Do any deferred work; a software backend has nothing to do, a GPU one
  /// submits its batches.
  fn flush(Self) -> Unit
}
