// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "each triangle contributes three indices and one draw call" {
  let builder = BatchBuilder::new()
  let triangles : Array[@moongfx.Triangle] = [
    {
      a: @moonmath.Vec2::new(0.0, 0.0),
      b: @moonmath.Vec2::new(10.0, 0.0),
      c: @moonmath.Vec2::new(0.0, 10.0),
    },
    {
      a: @moonmath.Vec2::new(10.0, 0.0),
      b: @moonmath.Vec2::new(10.0, 10.0),
      c: @moonmath.Vec2::new(0.0, 10.0),
    },
  ]
  builder.fill(triangles, @moongfx.solid(@moonrgba.Color::rgb(1, 2, 3)))
  let batch = builder.build()
  assert_eq(batch.triangle_count(), 2)
  assert_eq(batch.draw_count(), 1)
  assert_eq(batch.vertices.length(), 6)
  assert_eq(batch.indices.length(), 6)
}

///|
test "the second fill starts where the first stopped" {
  let builder = BatchBuilder::new()
  let one : Array[@moongfx.Triangle] = [
    {
      a: @moonmath.Vec2::new(0.0, 0.0),
      b: @moonmath.Vec2::new(1.0, 0.0),
      c: @moonmath.Vec2::new(0.0, 1.0),
    },
  ]
  builder.fill(one, @moongfx.solid(@moonrgba.Color::rgb(0, 0, 0)))
  builder.fill(one, @moongfx.solid(@moonrgba.Color::rgb(9, 9, 9)))
  let batch = builder.build()
  assert_eq(batch.draw_count(), 2)
  let second = batch.draws[1]
  assert_eq(second.first, 3)
  assert_eq(second.count, 3)
  // The second triangle's indices point at its own vertices, not at the first's.
  assert_eq(batch.indices[3], 3)
}

///|
test "a mask quad samples the cell it was given" {
  let builder = BatchBuilder::new()
  let source : @moongfx.Bounds = {
    min_x: 16.0,
    min_y: 8.0,
    max_x: 26.0,
    max_y: 22.0,
  }
  let quad = quad()
  builder.mask_quad(
    source,
    quad,
    @moongfx.solid(@moonrgba.Color::rgb(0, 0, 0)),
    5,
  )
  let batch = builder.build()
  assert_eq(batch.vertices.length(), 4)
  assert_eq(batch.indices.length(), 6)
  assert_eq(batch.vertices[0].texcoord.x, 16.0)
  assert_eq(batch.vertices[0].texcoord.y, 8.0)
  assert_eq(batch.vertices[2].texcoord.x, 26.0)
  assert_eq(batch.vertices[2].texcoord.y, 22.0)
  match batch.draws[0].texture {
    Coverage(layer) => assert_eq(layer, 5)
    _ => fail("the draw call did not name a coverage texture")
  }
}

///|
test "an image quad samples the whole image" {
  let builder = BatchBuilder::new()
  builder.image_quad(quad(), 40, 20, 2)
  let batch = builder.build()
  assert_eq(batch.vertices[2].texcoord.x, 40.0)
  assert_eq(batch.vertices[2].texcoord.y, 20.0)
  match batch.draws[0].texture {
    Colour(layer) => assert_eq(layer, 2)
    _ => fail("the draw call did not name a colour texture")
  }
}

///|
test "the clip in force is recorded on the draw call" {
  let builder = BatchBuilder::new()
  let one : Array[@moongfx.Triangle] = [
    {
      a: @moonmath.Vec2::new(0.0, 0.0),
      b: @moonmath.Vec2::new(1.0, 0.0),
      c: @moonmath.Vec2::new(0.0, 1.0),
    },
  ]
  builder.fill(one, @moongfx.solid(@moonrgba.Color::rgb(0, 0, 0)))
  builder.set_clip(7)
  builder.fill(one, @moongfx.solid(@moonrgba.Color::rgb(0, 0, 0)))
  let batch = builder.build()
  assert_eq(batch.draws[0].clip, 0)
  assert_eq(batch.draws[1].clip, 7)
}

///|
test "an empty fill adds nothing" {
  let builder = BatchBuilder::new()
  builder.fill([], @moongfx.solid(@moonrgba.Color::rgb(0, 0, 0)))
  assert_true(builder.build().is_empty())
}

///|
fn quad() -> @moongfx.Quad {
  let box : @moongfx.Bounds = {
    min_x: 10.0,
    min_y: 20.0,
    max_x: 30.0,
    max_y: 60.0,
  }
  @moongfx.Quad::of_bounds(box)
}
