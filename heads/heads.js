// The people on the site: one entry per head. tools/cut-heads.sh writes this file from the photos
// in photos/, so re-run that rather than editing by hand. (To change how a name is spelled, use
// `names` in config.js.)
//
//   id     who they are in the draw (lowercase, no spaces)
//   name   what's shown on the site
//   src    the cut-out picture
//   w, h   its size in pixels
//   crown  where the top of the head is, as a fraction of the picture [across, down]: the hat sits here
//   roll   how far the head is tilted in the picture, in degrees (clockwise)
//
window.HEADS = [
  { id: 'connor',  name: 'Connor',  src: 'heads/connor.webp',  w: 434, h: 504, crown: [0.5, 0.004], roll: 0 },
  { id: 'kyle',    name: 'Kyle',    src: 'heads/kyle.webp',    w: 390, h: 504, crown: [0.47, 0.042], roll: 0 },
  { id: 'nick',    name: 'Nick',    src: 'heads/nick.webp',    w: 631, h: 504, crown: [0.525, 0.004], roll: 0 },
  { id: 'patrick', name: 'Patrick', src: 'heads/patrick.webp', w: 415, h: 504, crown: [0.516, 0.026], roll: 0 },
  { id: 'ryan',    name: 'Ryan',    src: 'heads/ryan.webp',    w: 401, h: 504, crown: [0.524, 0.046], roll: 0 },
  { id: 'scott',   name: 'Scott',   src: 'heads/scott.webp',   w: 360, h: 504, crown: [0.495, 0.046], roll: 0 },
  { id: 'steven',  name: 'Steven',  src: 'heads/steven.webp',  w: 394, h: 504, crown: [0.509, 0.046], roll: 0 },
  { id: 'tj',      name: 'TJ',      src: 'heads/tj.webp',      w: 394, h: 504, crown: [0.473, 0.044], roll: 0 },
];
