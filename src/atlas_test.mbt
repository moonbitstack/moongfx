// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Whether two regions share any pixel inside them, borders excluded.
fn overlaps(a : @moongfx.Region, b : @moongfx.Region) -> Bool {
  a.x < b.x + b.width &&
  b.x < a.x + a.width &&
  a.y < b.y + b.height &&
  b.y < a.y + a.height
}

///|
test "cells packed side by side do not overlap" {
  let atlas = @moongfx.Atlas::new(64, 64)
  let cells : Array[@moongfx.Region] = []
  for _ in 0..<8 {
    match atlas.alloc(8, 8) {
      Some(region) => cells.push(region)
      None => fail("the atlas refused a cell that fits")
    }
  }
  assert_eq(cells.length(), 8)
  for i in 0..<cells.length() {
    for j in (i + 1)..<cells.length() {
      assert_true(!overlaps(cells[i], cells[j]))
    }
  }
  assert_true(atlas.fullness() > 0.0)
}

///|
test "a cell wider than the atlas is refused" {
  let atlas = @moongfx.Atlas::new(32, 32)
  match atlas.alloc(40, 4) {
    Some(_) => fail("a cell wider than the atlas was packed")
    None => ()
  }
  match atlas.alloc(0, 4) {
    Some(_) => fail("an empty cell was packed")
    None => ()
  }
}

///|
test "the atlas grows downwards when the shelves run out, and keeps what it has" {
  let atlas = @moongfx.Atlas::new(32, 32, max_height=256)
  let first = match atlas.alloc(30, 20) {
    Some(region) => region
    None => fail("the first cell did not fit")
  }
  let mut packed = 1
  while packed < 12 {
    match atlas.alloc(30, 20) {
      Some(_) => packed = packed + 1
      None => break
    }
  }
  assert_eq(packed, 12)
  assert_true(atlas.height() > 32)
  // The first cell kept its place through every growth.
  assert_eq(atlas.coverage(first.x, first.y), 0.0)
  let mask = @moongfx.Mask::new(30, 20)
  for i in 0..<mask.data.length() {
    mask.data[i] = b'\xFF'
  }
  atlas.write(first, mask)
  assert_eq(atlas.coverage(first.x, first.y), 1.0)
}

///|
test "an atlas that cannot grow refuses the cell instead of overlapping" {
  let atlas = @moongfx.Atlas::new(16, 16, max_height=16)
  let mut packed = 0
  while true {
    match atlas.alloc(15, 15) {
      Some(_) => packed = packed + 1
      None => break
    }
    if packed > 8 {
      fail("the atlas packed more cells than it can hold")
    }
  }
  assert_eq(packed, 1)
}

///|
test "clearing the atlas gives back the whole area" {
  let atlas = @moongfx.Atlas::new(32, 32)
  let region = match atlas.alloc(10, 10) {
    Some(region) => region
    None => fail("the cell did not fit")
  }
  let mask = @moongfx.Mask::new(10, 10)
  for i in 0..<mask.data.length() {
    mask.data[i] = b'\xFF'
  }
  atlas.write(region, mask)
  assert_true(atlas.fullness() > 0.0)
  atlas.clear()
  assert_eq(atlas.fullness(), 0.0)
  assert_eq(atlas.coverage(region.x, region.y), 0.0)
}

///|
test "a written cell holds the mask it was given" {
  let atlas = @moongfx.Atlas::new(16, 16)
  let mask = @moongfx.Mask::new(4, 4)
  mask.set(1, 1, 200)
  let region = match atlas.alloc(4, 4) {
    Some(region) => region
    None => fail("the cell did not fit")
  }
  atlas.write(region, mask)
  assert_eq(atlas.coverage(region.x + 1, region.y + 1) > 0.7, true)
  assert_eq(atlas.coverage(region.x + 2, region.y + 2), 0.0)
}
