"use strict";

const assert = require("node:assert/strict");
const fx = require(process.argv[2]);

const cream = { r: 0.96, g: 0.92, b: 0.82 };
const teal = { r: 0.1, g: 0.7, b: 0.65 };
const night = { r: 0.08, g: 0.08, b: 0.12 };

assert.equal(fx.mostVivid([night, cream, teal]), teal, "the burning edge is the most vivid colour, not the lightest");
assert.equal(fx.lightest([night, teal, cream]), cream, "the outline's ink is the lightest tone");

const near = (actual, expected) => actual.forEach((v, i) => assert.ok(Math.abs(v - expected[i]) < 1e-9, `${actual} != ${expected}`));
near(fx.cover(1920, 1080, 1920, 1080), [0, 0, 1, 1]);
// A 4:3 image on a 16:9 screen: full width, the middle 75 % of its height.
near(fx.cover(1600, 1200, 1920, 1080), [0, 0.125, 1, 0.75]);
// A 21:9 image on a 16:9 screen: full height, the middle of its width.
near(fx.cover(2560, 1080, 1920, 1080), [0.125, 0, 0.75, 1]);
near(fx.cover(0, 0, 1920, 1080), [0, 0.21875, 1, 0.5625]);

assert.equal(fx.fileUrl(""), "", "no path, no image");
assert.equal(fx.fileUrl("/home/me/Pictures/Wallpapers/b space.JPG"),
             "file:///home/me/Pictures/Wallpapers/b%20space.JPG");
assert.equal(fx.fileUrl("/w/#1 ?.png"), "file:///w/%231%20%3F.png", "'#' and '?' stay part of the name");

console.log("ok: WallpaperFxLogic.js");
