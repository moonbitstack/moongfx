// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a glyph is cached under: the code point and the size in quarter pixels,
/// which is finer than any rasteriser distinguishes and coarse enough that one
/// text run shares its glyphs.
#derive(Debug, Eq, Hash)
pub(all) struct GlyphKey {
  code : Int32
  size : Int32
}

///|
/// A glyph once it is in the atlas: where its coverage sits, where it draws, and
/// when it was last asked for.
#derive(Debug)
pub(all) struct GlyphEntry {
  region : Region
  left : Int32
  top : Int32
  advance : Float
  mut used : Int32
}

///|
/// The glyphs a text run needs, rasterised once each and packed into one atlas.
///
/// The cache owns the atlas, so a backend sees a single mask for every glyph in a
/// run and a text pass costs one texture upload rather than one per letter. A
/// glyph's rasterisation is asked of the source when it is missing, and never
/// again while it stays in the atlas.
pub struct GlyphCache {
  source : &GlyphSource
  atlas : Atlas
  mut entries : Map[GlyphKey, GlyphEntry]
  mut clock : Int32
  mut hits : Int32
  mut misses : Int32
  mut resets : Int32
}

///|
/// A cache whose atlas starts at `width` by `height` and may grow downwards to
/// `max_height`.
pub fn GlyphCache::new(
  source : &GlyphSource,
  width~ : Int32 = 512,
  height~ : Int32 = 512,
  max_height~ : Int32 = 2048,
) -> GlyphCache {
  {
    source,
    atlas: Atlas::new(width, height, max_height~),
    entries: Map([]),
    clock: 0,
    hits: 0,
    misses: 0,
    resets: 0,
  }
}

///|
/// The atlas the glyphs live in.
pub fn GlyphCache::atlas(self : GlyphCache) -> Atlas {
  self.atlas
}

///|
/// The atlas as a mask, which is what a backend samples.
pub fn GlyphCache::mask(self : GlyphCache) -> Mask {
  {
    width: self.atlas.width(),
    height: self.atlas.height(),
    data: self.atlas.data,
  }
}

///|
/// How many glyph lookups found their glyph already packed.
pub fn GlyphCache::hits(self : GlyphCache) -> Int32 {
  self.hits
}

///|
/// How many had to rasterise.
pub fn GlyphCache::misses(self : GlyphCache) -> Int32 {
  self.misses
}

///|
/// How many times the atlas was thrown away and rebuilt because it had no room.
pub fn GlyphCache::resets(self : GlyphCache) -> Int32 {
  self.resets
}

///|
/// The glyph for `code` at `size` pixels per em, rasterising and packing it the
/// first time.
pub fn GlyphCache::entry(
  self : GlyphCache,
  code : Char,
  size : Float,
) -> GlyphEntry? {
  let quarter = (size * 4.0).round().to_int()
  if quarter <= 0 {
    return None
  }
  let key = { code: code.to_int().to_int(), size: quarter, }
  match self.entries.get(key) {
    Some(entry) => {
      self.clock = self.clock + 1
      entry.used = self.clock
      self.hits = self.hits + 1
      Some(entry)
    }
    None => {
      self.misses = self.misses + 1
      let glyph = match self.source.glyph(code, as_float(quarter) / 4.0) {
        Some(glyph) => glyph
        None => return None
      }
      let width = glyph.mask.width()
      let height = glyph.mask.height()
      let mut region : Region = { x: 0, y: 0, width: 0, height: 0, }
      if width > 0 && height > 0 {
        let placed = match self.atlas.alloc(width, height) {
          Some(found) => Some(found)
          None => {
            // No room and no way to grow: drop the atlas and start again, which
            // keeps the glyphs a run actually repeats and costs a re-raster of
            // the ones it does not.
            self.reset()
            self.atlas.alloc(width, height)
          }
        }
        match placed {
          Some(found) => {
            self.atlas.write(found, glyph.mask)
            region = found
          }
          None => return None
        }
      }
      let entry = {
        region,
        left: glyph.left,
        top: glyph.top,
        advance: glyph.advance,
        used: 0,
      }
      self.clock = self.clock + 1
      entry.used = self.clock
      self.entries[key] = entry
      Some(entry)
    }
  }
}

///|
/// Empty the atlas and forget every entry.
fn GlyphCache::reset(self : GlyphCache) -> Unit {
  self.atlas.clear()
  self.entries = Map([])
  self.resets = self.resets + 1
}

///|
/// Draw `text` with its baseline starting at `at`, and return how far the pen
/// moved.
///
/// The size is in pixels per em of the source, the paint is applied through the
/// glyph's coverage, and the whole run goes through the current transform, so
/// text follows the same space as the paths around it.
pub fn Canvas::fill_text(
  self : Canvas,
  at : Vec2,
  text : StringView,
  size : Float,
  paint : Paint,
  cache : GlyphCache,
) -> Float {
  let mut pen = at.x
  let device_paint = device_paint(paint, self.transform)
  let atlas = cache.mask()
  for code in text {
    match cache.entry(code, size) {
      Some(entry) => {
        if !entry.region.is_empty() {
          let box = {
            min_x: pen + as_float(entry.left),
            min_y: at.y + as_float(entry.top),
            max_x: pen + as_float(entry.left + entry.region.width),
            max_y: at.y + as_float(entry.top + entry.region.height),
          }
          let quad = Quad::of_bounds(box).map(self.transform)
          self.backend.fill_mask(
            atlas,
            entry.region.bounds(),
            quad,
            device_paint,
          )
        }
        pen = pen + entry.advance
      }
      None => pen = pen + size * 0.5
    }
  }
  pen - at.x
}

///|
/// The width `text` will take at `size`, without drawing it.
pub fn measure_text(
  cache : GlyphCache,
  text : StringView,
  size : Float,
) -> Float {
  let mut width : Float = 0.0
  for code in text {
    match cache.entry(code, size) {
      Some(entry) => width = width + entry.advance
      None => width = width + size * 0.5
    }
  }
  width
}
