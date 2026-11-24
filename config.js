// Everything you'd want to change about the site lives in this file.
// (The people come from heads/heads.js, which tools/cut-heads.sh writes from your photos.)

window.CONFIG = {
  // The big title. Put *stars* around the word that should get the gold, tilted, wiggly treatment.
  title: 'Ho Ho *Who?*',

  // The small label above the title. Use '' to hide it.
  kicker: 'Secret Santa',

  // Optional line shown under the reveal, e.g. '$40 limit · swap on Dec 19'.
  details: '',

  // The draw. Any phrase works. Everyone's match is worked out from this phrase plus the list of
  // people, so the same phrase gives the same matches on every phone.
  //   → Pick your own before sharing the link.
  //   → Changing it later (or adding/removing a person) re-draws EVERYONE.
  seed: 'garland-chestnut-mitten-biscuit-8854',

  // Fix how a name is displayed without renaming the photo, e.g. { jd: 'JD', 'mary-kate': 'MK' }.
  // The key is the head's id in heads/heads.js.
  names: {},

  // Every word on the site. {me} is the person using the phone, {name} is the head in question.
  text: {
    lobby: 'Tap your own head',
    welcomeBack: 'Hi {me}. Tap your head to peek again.',
    youTag: '{name} · you',
    notMe: 'Not {me}?',

    confirmTitle: "You're {name}?",
    confirmSub: "Be honest. Santa's watching.",
    confirmYes: "Yep, that's my head",
    confirmNo: 'Nope',

    // One line per tap on the present: the first shows before any tap, and the present opens on the
    // tap after the last line. Two lines = two taps. Add a middle line (e.g. 'Who wrapped this?!')
    // for three.
    present: ['Open your present', 'ONE MORE!'],
    presentSub: 'Your person is in there, {me}',

    revealTitle: '{me}, you got',
    revealName: '{name}!',
    revealNote: 'Shhh. Tell no one.',
    back: 'Back to the gang',

    // Shown, in turn, when someone who has already picked taps somebody else's head.
    cheats: ['Nice try, {me}. Santa saw that.', "That's {name}'s business, {me}.", 'Keep it up and you get coal.'],

    resetTitle: 'Wrong head?',
    resetSub: 'Switching is for honest mistakes. Cheaters get coal.',
    resetYes: 'Switch heads',
    resetNo: 'Never mind',
  },
};
