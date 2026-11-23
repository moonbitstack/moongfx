// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The plane's point and direction type, re-exported from moonmath so that a
/// caller drawing with this library does not import two vector types.
pub using @moonmath {type Vec2, type Affine2}

///|
/// Half a turn in radians, as a float.
let half_turn : Float = 3.141592653589793

///|
/// A whole turn in radians, as a float.
let full_turn : Float = 6.283185307179586

///|
/// A count as a float, which the geometry needs for stepping along a curve.
fn as_float(n : Int32) -> Float {
  Float::from_double(Int32::to_double(n))
}

///|
/// A double as a float, for the points that leave the sweepline.
fn as_f32(d : Double) -> Float {
  Float::from_double(d)
}

///|
/// A float as a double, for the arithmetic that must not lose precision.
fn as_f64(x : Float) -> Double {
  x.to_double()
}
