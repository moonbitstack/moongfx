// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "the demo face draws a letter with ink in it" {
  let face = @moongfx.DemoFace::new()
  let glyph = match face.glyph('A', 16.0) {
    Some(glyph) => glyph
    None => fail("the face has no A")
  }
  assert_true(glyph.mask.width() > 0)
  assert_true(glyph.mask.height() > 0)
  assert_eq(glyph.advance, 12.0)
  // Cap height is seven of the eight cells, so the ink starts above the baseline.
  assert_true(glyph.top < 0)
  let mut inked = 0
  for y in 0..<glyph.mask.height() {
    for x in 0..<glyph.mask.width() {
      if glyph.mask.at(x, y) > 0 {
        inked = inked + 1
      }
    }
  }
  assert_true(inked > 0)
}

///|
test "a space has no ink but still moves the pen" {
  let face = @moongfx.DemoFace::new()
  let glyph = match face.glyph(' ', 16.0) {
    Some(glyph) => glyph
    None => fail("the face has no space")
  }
  assert_eq(glyph.mask.width(), 0)
  assert_eq(glyph.advance, 12.0)
}

///|
test "a lowercase letter is drawn as its capital" {
  let face = @moongfx.DemoFace::new()
  let upper = match face.glyph('Q', 20.0) {
    Some(glyph) => glyph
    None => fail("the face has no Q")
  }
  let lower = match face.glyph('q', 20.0) {
    Some(glyph) => glyph
    None => fail("the face has no q")
  }
  assert_eq(upper.mask.width(), lower.mask.width())
  assert_eq(upper.mask.height(), lower.mask.height())
}

///|
test "a code point the face does not have has no glyph" {
  let face = @moongfx.DemoFace::new()
  assert_true(face.glyph('~', 12.0) is None)
}

///|
test "the second look at a glyph comes from the cache" {
  let face = @moongfx.DemoFace::new()
  let cache = @moongfx.GlyphCache::new(face)
  let first = match cache.entry('M', 24.0) {
    Some(entry) => entry
    None => fail("the glyph was not packed")
  }
  let second = match cache.entry('M', 24.0) {
    Some(entry) => entry
    None => fail("the glyph disappeared")
  }
  assert_eq(cache.misses(), 1)
  assert_eq(cache.hits(), 1)
  assert_eq(first.region.x, second.region.x)
  assert_eq(first.region.y, second.region.y)
}

///|
test "a packed glyph sits inside the atlas" {
  let face = @moongfx.DemoFace::new()
  let cache = @moongfx.GlyphCache::new(face)
  let entry = match cache.entry('W', 32.0) {
    Some(entry) => entry
    None => fail("the glyph was not packed")
  }
  assert_true(entry.region.x >= 0)
  assert_true(entry.region.y >= 0)
  assert_true(entry.region.x + entry.region.width <= cache.atlas().width())
  assert_true(entry.region.y + entry.region.height <= cache.atlas().height())
  assert_true(
    cache.atlas().coverage(entry.region.x + 1, entry.region.y + 1) >= 0.0,
  )
}

///|
test "an atlas too small for a run of text is emptied rather than grown for ever" {
  let face = @moongfx.DemoFace::new()
  let cache = @moongfx.GlyphCache::new(face, width=32, height=32, max_height=64)
  for code in "ABCDEFGHIJKLMNOP".to_array() {
    let _ = cache.entry(code, 40.0)
  }
  assert_true(cache.resets() > 0)
  assert_true(cache.atlas().height() <= 64)
}

///|
test "the width a run will take is the sum of its advances" {
  let face = @moongfx.DemoFace::new()
  let cache = @moongfx.GlyphCache::new(face)
  let width = @moongfx.measure_text(cache, "ABC", 16.0)
  assert_eq(width, 36.0)
}
