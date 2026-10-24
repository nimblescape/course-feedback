// Repeatable random numbers: the same program gives the same output in every
// feedback run (mulberry32 with a fixed seed). Loaded with `node --import`; it
// changes nothing that the student program can see except the numbers.
let seed = 20261024;
Math.random = () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
