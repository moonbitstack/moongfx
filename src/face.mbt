// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One glyph, already rasterised: its coverage and where that coverage sits
/// relative to the pen.
///
/// The mask is in drawing space — y down, the origin at the pen position on the
/// baseline — which is the orientation a rasteriser produces and a backend
/// samples, so nothing has to be flipped later.
#derive(Debug)
pub(all) struct Glyph {
  mask : Mask
  /// Pixels from the pen position to the left edge of the mask.
  left : Int32
  /// Pixels from the baseline down to the top edge of the mask; negative above
  /// the baseline.
  top : Int32
  /// How far the pen moves once the glyph is drawn.
  advance : Float
}

///|
/// Where glyph outlines come from.
///
/// The contract is deliberately at the mask: a font library parses the file,
/// applies its hinting or its variable-font instance and hands back coverage at a
/// size, and the atlas only has to pack it. That is also the shape a GPU backend
/// wants, since the atlas ends up as one texture.
pub(open) trait GlyphSource {
  /// The glyph for `code` at `size` pixels per em, or nothing when the face has
  /// no such glyph.
  fn glyph(Self, code : Char, size : Float) -> Glyph?
  /// Distance from the baseline to the top of a line, in pixels.
  fn ascent(Self, size : Float) -> Float
  /// Distance from the baseline to the bottom of a line, in pixels.
  fn descent(Self, size : Float) -> Float
}

///|
/// A face whose letters are drawn on a five by seven grid, one cell a pixel at
/// size eight.
///
/// It exists so that text can be drawn, and compared against a reference, with no
/// font file and no I/O: the outlines are rectangles, so every stage between the
/// grid and the frame buffer is the same one a real face goes through. Capitals
/// only — a lowercase letter is drawn as its capital.
pub struct DemoFace {
  rows : Array[(Char, Array[Int32])]
}

///|
/// The face.
pub fn DemoFace::new() -> DemoFace {
  { rows: demo_rows(), }
}

///|
/// The rows of one code point, as five-bit masks from the top down.
fn DemoFace::pattern(self : DemoFace, code : Char) -> Array[Int32]? {
  let wanted = code.to_ascii_uppercase()
  for entry in self.rows {
    if entry.0 == wanted {
      return Some(entry.1)
    }
  }
  None
}

///|
/// The glyph drawn from the grid.
pub impl GlyphSource for DemoFace with fn glyph(self, code, size) {
  let pattern = match self.pattern(code) {
    Some(pattern) => pattern
    None => return None
  }
  let cell = size / 8.0
  if cell <= 0.0 {
    return None
  }
  let builder = Path::builder()
  let mut painted = false
  for row in 0..<7 {
    let bits = pattern[row]
    for column in 0..<5 {
      if ((bits >> (4 - column)) & 1) == 0 {
        continue
      }
      let x = as_float(column) * cell
      let y = as_float(row - 7) * cell
      let _ = builder.rect({
        min_x: x,
        min_y: y,
        max_x: x + cell,
        max_y: y + cell,
      })
      painted = true
    }
  }
  if !painted {
    return Some({ mask: Mask::new(0, 0), left: 0, top: 0, advance: cell * 6.0, })
  }
  let path = builder.build()
  let box = path.bounds()
  let left = box.min_x.floor().to_int() - 1
  let top = box.min_y.floor().to_int() - 1
  let width = box.max_x.ceil().to_int() + 1 - left
  let height = box.max_y.ceil().to_int() + 1 - top
  if width <= 0 || height <= 0 {
    return None
  }
  let shifted = path.transform(
    Affine2::from_translation(Vec2::new(as_float(-left), as_float(-top))),
  )
  let mask = rasterize(fill(shifted, flatten=Flatten::new(0.05)), width, height)
  Some({ mask, left, top, advance: cell * 6.0, })
}

///|
pub impl GlyphSource for DemoFace with fn ascent(self, size) {
  let _ = self
  size * 7.0 / 8.0
}

///|
pub impl GlyphSource for DemoFace with fn descent(self, size) {
  let _ = self
  size / 8.0
}

///|
/// The face's trait methods are callable directly, so a caller can ask a face for
/// a glyph without naming the trait.
pub extend DemoFace with GlyphSource::{glyph, ascent, descent}

///|
/// The grid, as five-bit rows from the top: a one is a filled cell.
fn demo_rows() -> Array[(Char, Array[Int32])] {
  [
    (' ', [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000]),
    ('A', [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]),
    ('B', [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110]),
    ('C', [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110]),
    ('D', [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110]),
    ('E', [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111]),
    ('F', [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000]),
    ('G', [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111]),
    ('H', [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]),
    ('I', [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]),
    ('J', [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100]),
    ('K', [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001]),
    ('L', [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111]),
    ('M', [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001]),
    ('N', [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001]),
    ('O', [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]),
    ('P', [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000]),
    ('Q', [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10011, 0b01101]),
    ('R', [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001]),
    ('S', [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110]),
    ('T', [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100]),
    ('U', [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]),
    ('V', [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100]),
    ('W', [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001]),
    ('X', [0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b01010, 0b10001]),
    ('Y', [0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100]),
    ('Z', [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111]),
    ('0', [0b01110, 0b10011, 0b10101, 0b10101, 0b10101, 0b11001, 0b01110]),
    ('1', [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]),
    ('2', [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]),
    ('3', [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110]),
    ('4', [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010]),
    ('5', [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110]),
    ('6', [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110]),
    ('7', [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000]),
    ('8', [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110]),
    ('9', [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100]),
    ('.', [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b01100, 0b01100]),
    (',', [0b00000, 0b00000, 0b00000, 0b00000, 0b01100, 0b01100, 0b01000]),
    (':', [0b00000, 0b01100, 0b01100, 0b00000, 0b01100, 0b01100, 0b00000]),
    (';', [0b00000, 0b01100, 0b01100, 0b00000, 0b01100, 0b01000, 0b01000]),
    ('-', [0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000]),
    ('+', [0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000]),
    ('=', [0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000]),
    ('!', [0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100]),
    ('?', [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b00000, 0b00100]),
    ('/', [0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000]),
    ('%', [0b11001, 0b11010, 0b00010, 0b00100, 0b01000, 0b01011, 0b10011]),
    ('(', [0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010]),
    (')', [0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000]),
    ('#', [0b01010, 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0b01010]),
  ]
}
