// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A drawing surface you hand paths, strokes and paints to, in whatever
/// coordinates suit you.
///
/// The canvas holds the transform and the clip stack and does the geometry —
/// moving a path into device space, tessellating it, rasterising a clip — so a
/// backend receives only triangles and masks. That split is why the same program
/// draws into the software rasteriser and, once one exists, into a GPU pipeline
/// without changing a line.
pub struct Canvas {
  backend : &Backend
  mut transform : Affine2
  mut clip_depth : Int32
  /// The transforms `save` recorded, and the clip depth that went with each.
  saved_transforms : Array[Affine2]
  saved_depths : Array[Int32]
}

///|
/// A canvas drawing into `backend`, with an identity transform and no clip.
pub fn Canvas::new(backend : &Backend) -> Canvas {
  {
    backend,
    transform: Affine2::identity(),
    clip_depth: 0,
    saved_transforms: [],
    saved_depths: [],
  }
}

///|
/// The width of the target in pixels.
pub fn Canvas::width(self : Canvas) -> Int32 {
  self.backend.width()
}

///|
/// The height of the target in pixels.
pub fn Canvas::height(self : Canvas) -> Int32 {
  self.backend.height()
}

///|
/// The transform from the coordinates the caller draws in to device pixels.
pub fn Canvas::device_transform(self : Canvas) -> Affine2 {
  self.transform
}

///|
/// Remember the transform and the depth of the clip stack.
pub fn Canvas::save(self : Canvas) -> Unit {
  self.saved_transforms.push(self.transform)
  self.saved_depths.push(self.clip_depth)
}

///|
/// Go back to the transform and clip of the matching `save`, undoing any clip
/// pushed since.
pub fn Canvas::restore(self : Canvas) -> Unit {
  match self.saved_transforms.pop() {
    Some(transform) => {
      let depth = self.saved_depths.pop()
      self.transform = transform
      let target = depth.unwrap_or(0)
      while self.clip_depth > target {
        self.backend.pop_clip()
        self.clip_depth = self.clip_depth - 1
      }
    }
    None => ()
  }
}

///|
/// Draw in a space moved by `affine`.
pub fn Canvas::apply(self : Canvas, affine : Affine2) -> Unit {
  self.transform = self.transform * affine
}

///|
/// Move the origin.
pub fn Canvas::translate(self : Canvas, x : Float, y : Float) -> Unit {
  self.apply(Affine2::from_translation(Vec2::new(x, y)))
}

///|
/// Scale both axes.
pub fn Canvas::scale(self : Canvas, x : Float, y : Float) -> Unit {
  self.apply(Affine2::from_scale(Vec2::new(x, y)))
}

///|
/// Turn the axes anticlockwise by `radians` in a space whose y points up; on a
/// screen whose y points down the shape turns the other way, which is what the
/// arithmetic of the space says.
pub fn Canvas::rotate(self : Canvas, radians : Float) -> Unit {
  self.apply(Affine2::from_angle(radians))
}

///|
/// Fill everything with one colour, replacing what was there.
pub fn Canvas::clear(self : Canvas, color : @moonrgba.Color) -> Unit {
  self.backend.clear(color)
}

///|
/// The paint moved into device space, so that a backend can evaluate it at a
/// device pixel without knowing the transform.
fn device_paint(paint : Paint, transform : Affine2) -> Paint {
  match paint {
    Solid(_) => paint
    Linear(gradient) =>
      Linear({
        from: transform.transform_point(gradient.from),
        to: transform.transform_point(gradient.to),
        ramp: gradient.ramp,
      })
    Radial(gradient) =>
      Radial({ ..gradient, space: transform * gradient.space, })
    Texture(pattern) =>
      Texture({ ..pattern, transform: transform * pattern.transform, })
  }
}

///|
/// The flattening a fill uses, in device pixels.
fn device_tolerance(flatten : Flatten) -> Flatten {
  flatten
}

///|
/// Fill `path` under `rule`.
pub fn Canvas::fill(
  self : Canvas,
  path : Path,
  paint : Paint,
  rule~ : FillRule = NonZero,
  flatten~ : Flatten = standard,
) -> Unit {
  let device = path.transform(self.transform)
  let triangles = fill(device, rule~, flatten=device_tolerance(flatten))
  self.backend.fill_triangles(triangles, device_paint(paint, self.transform))
}

///|
/// Stroke `path` with `style`.
pub fn Canvas::stroke_path(
  self : Canvas,
  path : Path,
  style : Stroke,
  paint : Paint,
  flatten~ : Flatten = standard,
) -> Unit {
  let device = path.transform(self.transform)
  let triangles = stroke(device, style, flatten=device_tolerance(flatten))
  self.backend.fill_triangles(triangles, device_paint(paint, self.transform))
}

///|
/// Fill a rectangle.
pub fn Canvas::fill_rect(self : Canvas, box : Bounds, paint : Paint) -> Unit {
  let path = Path::builder().rect(box).build()
  self.fill(path, paint)
}

///|
/// Fill a rectangle with round corners.
pub fn Canvas::fill_rounded_rect(
  self : Canvas,
  box : Bounds,
  corners : Corners,
  paint : Paint,
) -> Unit {
  let path = Path::builder().rounded_rect(box, corners).build()
  self.fill(path, paint)
}

///|
/// Stroke a rectangle with round corners.
pub fn Canvas::stroke_rounded_rect(
  self : Canvas,
  box : Bounds,
  corners : Corners,
  style : Stroke,
  paint : Paint,
) -> Unit {
  let path = Path::builder().rounded_rect(box, corners).build()
  self.stroke_path(path, style, paint)
}

///|
/// Fill a circle.
pub fn Canvas::fill_circle(
  self : Canvas,
  centre : Vec2,
  radius : Float,
  paint : Paint,
) -> Unit {
  let path = Path::builder().circle(centre, radius).build()
  self.fill(path, paint)
}

///|
/// Stroke a circle.
pub fn Canvas::stroke_circle(
  self : Canvas,
  centre : Vec2,
  radius : Float,
  style : Stroke,
  paint : Paint,
) -> Unit {
  let path = Path::builder().circle(centre, radius).build()
  self.stroke_path(path, style, paint)
}

///|
/// Narrow everything drawn from now on to the inside of `path`.
pub fn Canvas::clip(
  self : Canvas,
  path : Path,
  rule~ : FillRule = NonZero,
  flatten~ : Flatten = standard,
) -> Unit {
  let device = path.transform(self.transform)
  let triangles = fill(device, rule~, flatten=device_tolerance(flatten))
  let mask = rasterize(triangles, self.backend.width(), self.backend.height())
  self.backend.push_clip(mask)
  self.clip_depth = self.clip_depth + 1
}

///|
/// Draw an image through a quad given in the coordinates the caller draws in.
pub fn Canvas::draw_image(
  self : Canvas,
  image : @moonimage.Image,
  quad : Quad,
  opacity~ : Float = 1.0,
) -> Unit {
  self.backend.draw_image(image, quad.map(self.transform), opacity)
}

///|
/// Draw an image into a box, stretched to fit it.
pub fn Canvas::draw_image_in(
  self : Canvas,
  image : @moonimage.Image,
  box : Bounds,
  opacity~ : Float = 1.0,
) -> Unit {
  self.draw_image(image, Quad::of_bounds(box), opacity~)
}

///|
/// Let the backend do whatever it defers.
pub fn Canvas::flush(self : Canvas) -> Unit {
  self.backend.flush()
}
