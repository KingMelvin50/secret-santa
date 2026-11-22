# Guide for the AI agent setting this up

You are helping someone turn this template into a Secret Santa site for their own friend group.
They are probably not a programmer. Do the work yourself, explain things in plain language, and
show them pictures (the cut-out sheet, the share image, the running site) rather than code.

## What this is

A static website with no build step and no server. Everyone in the group opens the same link, taps
their own floating head, taps a present, and sees who they are buying for.

| File | What it is | Who edits it |
| --- | --- | --- |
| `config.js` | Title, labels, every word on the site, the draw phrase (`seed`) | You, for almost every request |
| `heads/heads.js` | The list of people | `tools/cut-heads.sh` writes it |
| `heads/*.webp` | The cut-out heads | `tools/cut-heads.sh` writes them |
| `index.html` | The site. Link-preview tags at the top, colours in `:root` | Only those two parts, normally |
| `share.jpg` | Picture shown when the link is pasted in a chat | `tools/make-share-image.sh` writes it |
| `photos/` | The original photos. Never committed, never uploaded | The human |
| `tools/tunes.json` | Per-person fixes for the head cutter | You |
| `vercel.json`, `.vercelignore` | Hosting settings: no search indexing, no photos uploaded | Leave alone |

## Four rules

1. **No spoilers.** The organiser is almost always in the draw. Never show, print, log or describe
   who anyone gets on the real site. Test only with `?test` on the end of the address: it uses
   random fake matches and saves nothing. On the real address, do not tap the present. Do not run
   the draw function with the real seed and look at the result.
2. **Faces are private.** `photos/` stays on this computer (it is ignored by git and by the deploy).
   Do not send photos to an online service without asking first. If the project goes on GitHub, make
   the repository private: `heads/` contains real faces. Leave the `noindex` settings in place.
3. **The draw is fixed by `seed` + the list of people.** Changing either one re-draws everyone. That
   is fine before the link is shared. After it is shared, stop and explain this before changing
   anything: everyone would have to open the site again, and people may already have bought gifts.
4. **Ask before publishing.** Deploying puts faces on the public internet. Get a clear yes, then
   tell them the address.

## Setting it up

### 1. Ask what you need, all at once

- What should the site be called, and which word is the punchline? (It gets the gold wiggly
  treatment. Example: `Ho Ho *Who?*`.)
- Keep the small "Secret Santa" label above it, or change it?
- Anything to show after the reveal, like a budget or a date? (`details`)
- Are the photos in `photos/`, one per person, with each file named after the person?
- What should the group be called on the "Back to the ..." button? (`text.back`)
- Where should it go online, and is there a name they want in the link?

### 2. Cut out the heads (on a Mac)

```
sh tools/cut-heads.sh
```

This finds the biggest face in each photo, cuts out the head, adds a sticker border, writes
`heads/<name>.webp`, rewrites `heads/heads.js`, and removes the example cartoon heads. It needs
Apple's command line tools (`xcode-select --install`). If `cwebp` is missing it writes larger `.png`
files instead; `brew install webp` fixes that but is optional.

The file name is the person's name: `Mary Kate.jpg` is shown as "Mary Kate". An all-lowercase name
is capitalised for you. To change how a name is displayed without renaming the photo, use `names` in
`config.js`.

Then **open `photos/_cutouts.png` and look at every head**, and show it to the human. Common
problems and the fix, as an entry in `tools/tunes.json` keyed by the person's lowercase name:

| What you see | Try |
| --- | --- |
| A hand, arm or another person attached above the ears | `{"skullW": 1.12, "skullH": 1.15}` keeps a rounded cap instead of everything above the ears |
| Extra stuff on one side only (a hand against the cheek, a turned head) | `{"sxTopRight": 1.03}` or `{"sxTopLeft": 1.03}`, plus `skullWRight` / `skullWLeft` near `1.0` if a cap is on |
| A plain studio backdrop came along with the head | `{"bgKey": 42}` (raise it to remove more, lower it if it eats the face) |
| Collar, hood or shoulder showing at the sides | lower `sxTop` (default `1.38`) towards `1.15`, or lower `earEnd` (default `0.38`) |
| An ear or sideburn is clipped | raise `sxTop` towards `1.5` |
| A tall hat is cut off at the top | raise `cropUp` (default `1.7`) |
| Chin or beard clipped | raise `chinDrop` (default `0.07`) towards `0.15` |
| "no face found" | The face is too small, turned away or covered. Ask for another photo |

"Left" and "right" are the sides of the photo as you look at it. Every setting is described at the
top of `tools/extract-heads.swift`. Change one thing, run the script again, look again. If a photo
has several people in it, the cutter takes the biggest face, so crop the photo if it picks the
wrong person.

Example `tools/tunes.json`:

```json
{
  "sam": { "skullW": 1.12, "skullH": 1.15, "sxTopRight": 1.03, "skullWRight": 1.01 },
  "jo": { "bgKey": 42 }
}
```

#### No Mac?

The cutter only runs on macOS. Anything else that produces the following will work:

- One picture per person in `heads/`, with a **transparent background**, cropped tight to the head
  (hair, hat and ears in; neck and shoulders out), about 500 pixels tall, as `.webp` or `.png`.
  A white outline about 3% of the height makes it look like a sticker, but is optional.
- One line per person in `heads/heads.js`, in the same shape as the examples there:
  `id` (lowercase, no spaces), `name`, `src`, `w` and `h` (the picture's size in pixels),
  `crown` (where the top of the head is, as fractions across and down, usually about `[0.5, 0.05]`;
  the Santa hat sits there) and `roll` (how many degrees the head is tilted clockwise; `0` is fine).
  Leave out `example: true`.

Ways to get there: a background-removal library you run locally (for example `rembg` in Python) and
a crop; or the human can lift each head out of a photo on their phone and send you the PNGs. Online
background removers work too, but they upload the photos, so ask first.

### 3. Fill in `config.js`

- `title`, `kicker`, `details`.
- `seed`: replace it with a new random phrase (a few random words is plenty). Do this once, before
  the link is shared, and then leave it alone.
- `text.back`: "Back to the gang" becomes whatever the group is called.
- Everything else in `text` is optional. `text.present` controls the present: one line per tap, so
  two lines means two taps and three lines means three.

### 4. Fill in the link preview at the top of `index.html`

Six lines between the `LINK PREVIEW` comments: the site's name (three places) and its address (three
places). The address isn't known until step 7, so come back to it.

### 5. Make the share picture

```
sh tools/make-share-image.sh
```

Needs Google Chrome on a Mac. Open `share.jpg`, check it, and show the human. Run it again whenever
the title or the heads change. Without Chrome or a Mac: open `tools/share-image.html` in a browser
at exactly 1200×630 and save a screenshot as `share.jpg`.

### 6. Test it without spoiling it

Open the site with `?test` on the end. Either open `index.html` straight from the folder, or serve
the folder (`python3 -m http.server 4173`, then `http://localhost:4173/?test`).

Check, in test mode:

- Every head appears, with the right name, and none is distorted.
- Tap a head → "You're (name)?" → yes → tap the present until it opens → a name is revealed, with a
  Santa hat sitting on top of the head (not floating above it or over the eyes).
- Long names and a long title fit on a phone-sized screen.
- The yellow **Test mode** pill top left. If it says "to do", tap it: it lists what still looks
  like the template (example heads, default seed, link preview not filled in). The same reminders
  go to the browser console as `[setup]` warnings.

Things that will otherwise waste your time:

- The animation only runs in a visible browser tab. In a hidden, background or headless tab the
  heads never fall in. That is the browser pausing animation, not a bug. Check the logic through
  the page's state (`#arena` has `data-state`: `lobby`, `confirm`, `draw`, `reveal`) and ask the
  human to look at the motion.
- Calling `.click()` on a head, a button or the present works for scripted run-throughs.
- Test mode picks new random matches on every load. Real mode gives the same answer every time.

### 7. Put it online

Any static host works. Only these belong online: `index.html`, `config.js`, `heads/`, `share.jpg`
(and `vercel.json` on Vercel). `sh tools/make-site-folder.sh` copies exactly those into `_site/`,
for hosts where you drag and drop a folder.

What worked when this template was made (Vercel, free plan, CLI v59; check `vercel help` if a
command has changed):

```
npm i -g vercel                                  # needs Node.js
vercel login                                     # the human signs in or makes a free account
vercel project add my-santa-site                 # the name becomes my-santa-site.vercel.app if it's free
vercel link --yes --project my-santa-site
vercel deploy --prod --yes
vercel domains add other-name.vercel.app my-santa-site   # optional: a different address for the same site
```

`.vercelignore` keeps `photos/` and `tools/` from being uploaded. Do not delete it.

Then:

1. Put the real address into the three address lines of the link preview in `index.html`, and
   deploy again.
2. Check the live site: the page loads; `/share.jpg` loads; `/photos/` and `/tools/` give "not
   found"; and the whole flow works at `https://THE-ADDRESS/?test`.
3. Give the human the link, and suggest a message for the group chat, for example: "Secret Santa
   time. Tap your own head, open the present, tell no one. Reply 🎅 when you've done it."

GitHub Pages also works, but on a free account it needs a public repository, which makes everyone's
cut-out face public on GitHub. Prefer a host that deploys straight from this folder.

## Things people ask for

| Request | Where |
| --- | --- |
| Rename the site, change the highlighted word | `title` in `config.js`, the link-preview lines in `index.html`, then `tools/make-share-image.sh` |
| Change any wording | `text` in `config.js` |
| More or fewer taps on the present | `text.present` in `config.js`: one line per tap |
| Show the budget or the date | `details` in `config.js` |
| Fix how a name is spelled | `names` in `config.js` |
| Fix a bad cut-out | `tools/tunes.json`, then `tools/cut-heads.sh` (table above) |
| Different colours | The `:root` block at the top of `index.html`, and the matching one in `tools/share-image.html`, then re-make the share picture |
| Not Christmas (birthday swap, white elephant) | Wording in `config.js`; colours as above; the Santa hat is the `HAT` drawing and the present is the `#present` drawing in `index.html` |
| A different link | Add another address on the host, then update the link-preview lines |
| Add or remove someone **before** the link is shared | Change `photos/`, run `tools/cut-heads.sh`, re-make the share picture |
| Add or remove someone **after** the link is shared | Rule 3: explain that everyone gets re-drawn, and get a yes first |
| "Did everyone do it?" | The site keeps no records. Ask the group to reply 🎅 in the chat |

## How the draw works (for when they ask "is this going to work?")

- Everyone's id is sorted by a hash of `seed` + id. That puts the group in one ring, and each
  person buys for the next person round the ring. See `drawRing` in `index.html`.
- So: nobody gets themselves, everybody gives one gift and gets one gift, no two people simply swap
  with each other (with three or more people), and every phone works out the same answer without a
  server or database.
- A phone remembers whose head was tapped (in the browser's local storage), so opening the link
  again shows the same person. "Not (name)?" lets someone fix an honest mis-tap.
- It is an honour system. Nothing stops a determined person from tapping someone else's head on
  another device, or reading the page source. The site scolds people who try. For a group of friends
  that is the right amount of security; say so if asked.
- The site cannot tell who has drawn. If that matters, the group chat is the tracker.
- If the link preview in a chat app looks stale after a change, the app has cached it: send the link
  with `?v=2` on the end.
