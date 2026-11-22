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
// These six are placeholders so the site works out of the box.
window.HEADS = [
  { id: 'alex',  name: 'Alex',  src: 'heads/alex.svg',  w: 364, h: 424, crown: [0.5, 0.047], roll: 0, example: true },
  { id: 'jo',    name: 'Jo',    src: 'heads/jo.svg',    w: 364, h: 436, crown: [0.5, 0.041], roll: 0, example: true },
  { id: 'max',   name: 'Max',   src: 'heads/max.svg',   w: 364, h: 387, crown: [0.5, 0.047], roll: 0, example: true },
  { id: 'pat',   name: 'Pat',   src: 'heads/pat.svg',   w: 364, h: 472, crown: [0.5, 0.038], roll: 0, example: true },
  { id: 'riley', name: 'Riley', src: 'heads/riley.svg', w: 364, h: 462, crown: [0.5, 0.039], roll: 0, example: true },
  { id: 'sam',   name: 'Sam',   src: 'heads/sam.svg',   w: 380, h: 450, crown: [0.5, 0.036], roll: 0, example: true },
];
