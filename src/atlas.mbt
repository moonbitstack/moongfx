// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A rectangle inside a mask or an atlas, in pixels.
#derive(Debug, Eq)
pub(all) struct Region {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
}

///|
/// The region as a box, for the backend calls that take one.
pub fn Region::bounds(self : Region) -> Bounds {
  {
    min_x: as_float(self.x),
    min_y: as_float(self.y),
    max_x: as_float(self.x + self.width),
    max_y: as_float(self.y + self.height),
  }
}

///|
/// Whether the region holds any pixels.
pub fn Region::is_empty(self : Region) -> Bool {
  self.width <= 0 || self.height <= 0
}

///|
/// One horizontal band of an atlas, with the height of its tallest cell and how
/// far along it the next cell goes.
pub struct Shelf {
  y : Int32
  height : Int32
  mut cursor : Int32
}

///|
/// A coverage atlas packed in shelves.
///
/// Shelves are the cheapest packing that wastes little on glyphs, which are all
/// about the same height in a run of text: a glyph goes on the first shelf tall
/// enough with room left, and a new shelf is started below the last when none has
/// room. Each cell keeps one pixel of padding so that a bilinear sample cannot
/// read a neighbour.
///
/// The atlas grows by doubling its height while it may, and the caller evicts by
/// clearing it and adding back the glyphs worth keeping — a glyph cache knows
/// which those are, an atlas does not.
pub struct Atlas {
  width : Int32
  mut height : Int32
  max_height : Int32
  mut shelves : Array[Shelf]
  /// The coverage, one byte a pixel, row by row.
  mut data : Array[Byte]
  /// How much of the area is spoken for, which is how full the atlas is.
  mut occupied : Int32
}

///|
/// An empty atlas.
pub fn Atlas::new(
  width : Int32,
  height : Int32,
  max_height~ : Int32 = 2048,
) -> Atlas {
  let width = if width < 1 { 1 } else { width }
  let height = if height < 1 { 1 } else { height }
  {
    width,
    height,
    max_height: if max_height < height {
      height
    } else {
      max_height
    },
    shelves: [],
    data: Array::make(width * height, b'\x00'),
    occupied: 0,
  }
}

///|
/// The atlas width in pixels.
pub fn Atlas::width(self : Atlas) -> Int32 {
  self.width
}

///|
/// The atlas height in pixels.
pub fn Atlas::height(self : Atlas) -> Int32 {
  self.height
}

///|
/// The area spoken for, in pixels.
pub fn Atlas::occupied(self : Atlas) -> Int32 {
  self.occupied
}

///|
/// The share of the atlas in use, from zero to one.
pub fn Atlas::fullness(self : Atlas) -> Float {
  as_float(self.occupied) / as_float(self.width * self.height)
}

///|
/// A cell `width` by `height` with room for the glyph and its padding, or nothing
/// when the atlas has no room left.
///
/// The cell grows the atlas first when it may, so a caller only sees a failure
/// once the atlas is at its largest.
pub fn Atlas::alloc(self : Atlas, width : Int32, height : Int32) -> Region? {
  if width <= 0 || height <= 0 || width + 1 > self.width {
    return None
  }
  let region = self.place(width, height)
  if region is Some(_) {
    return region
  }
  while self.height < self.max_height {
    let before = self.height
    self.grow()
    if self.height == before {
      break
    }
    let region = self.place(width, height)
    if region is Some(_) {
      return region
    }
  }
  None
}

///|
/// The first shelf with room for a cell, or a new shelf when none has.
fn Atlas::place(self : Atlas, width : Int32, height : Int32) -> Region? {
  let needed = width + 1
  for i in 0..<self.shelves.length() {
    let shelf = self.shelves[i]
    if shelf.height >= height + 1 && shelf.cursor + needed <= self.width {
      let region = { x: shelf.cursor, y: shelf.y, width, height, }
      shelf.cursor = shelf.cursor + needed
      self.occupied = self.occupied + width * height
      return Some(region)
    }
  }
  let bottom = self.used_height()
  if bottom + height + 1 > self.height {
    return None
  }
  self.shelves.push({ y: bottom, height: height + 1, cursor: needed, })
  self.occupied = self.occupied + width * height
  Some({ x: 0, y: bottom, width, height, })
}

///|
/// The bottom of the lowest shelf, where the next one starts.
fn Atlas::used_height(self : Atlas) -> Int32 {
  let mut bottom = 0
  for shelf in self.shelves {
    let end = shelf.y + shelf.height
    if end > bottom {
      bottom = end
    }
  }
  bottom
}

///|
/// Double the height, keeping what is already packed.
fn Atlas::grow(self : Atlas) -> Unit {
  let old_height = self.height
  let new_height = if old_height * 2 > self.max_height {
    self.max_height
  } else {
    old_height * 2
  }
  if new_height <= old_height {
    return
  }
  let grown : Array[Byte] = Array::make(self.width * new_height, b'\x00')
  for i in 0..<(self.width * old_height) {
    grown[i] = self.data[i]
  }
  self.data = grown
  self.height = new_height
}

///|
/// Throw everything away, ready for a fresh pack.
pub fn Atlas::clear(self : Atlas) -> Unit {
  self.shelves = []
  self.occupied = 0
  for i in 0..<self.data.length() {
    self.data[i] = b'\x00'
  }
}

///|
/// Copy a mask into the cell, and its origin into the shelf, so the atlas is
/// ready to be sampled.
pub fn Atlas::write(self : Atlas, region : Region, mask : Mask) -> Unit {
  if region.is_empty() {
    return
  }
  for y in 0..<region.height {
    let from = y * mask.width()
    let to = (region.y + y) * self.width + region.x
    for x in 0..<region.width {
      if x < mask.width() && y < mask.height() {
        self.data[to + x] = mask.data[from + x]
      }
    }
  }
}

///|
/// The coverage at a point of the atlas.
pub fn Atlas::coverage(self : Atlas, x : Int32, y : Int32) -> Float {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    return 0.0
  }
  as_float(self.data[y * self.width + x].to_int()) / 255.0
}
