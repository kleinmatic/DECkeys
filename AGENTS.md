# AGENTS.md — adding keyboard layouts and overlays

This file is for an AI agent asked to extend DECkeys. Read
[README.md](README.md) first for what the program is.

**Almost everything worth adding here is data.** `profile.json` is read at
launch; keys, layout, sizes and legends can all change without touching Swift,
without rebuilding, and — importantly — without invalidating the app's
Accessibility grant. Reach for the code only when a genuinely new *capability*
is needed.

---

## The one rule that matters

**Never write a legend from memory. Find the diagram.**

This is not a style preference. When this project began, the EDT keypad was
filled in from recollection. It turned out to be an accurate memory of *EDT* —
and completely wrong as a description of **EVE's EDT-keypad emulation**, which
is what the user was actually running. EVE renames `CUT`/`PASTE` to
`Remove`/`Insert Here`, `ADVANCE`/`BACKUP` to `Forward`/`Reverse`, and
`UND L/W/C` to `Res Lin/Wor/Cha`. Six of eighteen legends were wrong, and
confidently so.

Every one of these applications will draw you its own keypad:

| Application | How to get the diagram |
|---|---|
| EVE | `GOLD-HELP` inside the editor |
| EDT | `HELP KEYPAD` |
| VAX Notes | **PF2** or **Help** at the `Notes>` prompt |
| Most DEC software | its `HELP` key, or the printed manual |

And DEC's manuals are scanned on [bitsavers](https://bitsavers.trailing-edge.com/pdf/dec/),
with keypad figures carrying identifiers like `ZK-1688-84`. **Cite the figure
number in the profile comments** so the next person can check your work.

If you cannot find a diagram, say so and stop. A wrong legend is worse than a
blank one: a blank cap says "unknown", a wrong cap says "this key does X" and
will be believed.

---

## Adding an overlay

An overlay is one entry in `legends`, keyed by key label:

```json
"MAIL": {
  "PF1":  { "legend": "GOLD", "goldCap": true },
  "PF3":  { "legend": "EXTRACT", "note": "EXTRACT/MAIL", "gold": "EXTRACT" },
  "-":    { "legend": "READ/NEW", "gold": "SHOW/NEW" }
}
```

| Field | Meaning |
|---|---|
| `legend` | the unshifted function, drawn under the key label |
| `gold` | the Gold-prefixed function — shown in the tooltip, since there is no room for a third line |
| `note` | the full wording when `legend` had to be abbreviated to fit |
| `goldCap` | paint this cap gold |

Conventions that carry real meaning:

- **Blank is information.** If the diagram shows a key with no function, leave
  it out of the set. In `NOTES`, PF3 and KP4/6/8/9 genuinely do nothing —
  showing them blank tells the user which keys are safe to press.
- **`goldCap` belongs to the set, not the key.** PF1 is only gold when an
  application treats it as a prefix. Under "None" it is just PF1.
- **Keep `legend` short.** Roughly eleven characters fit a 54-point cap. Put the
  real wording in `note` — "PREVIOUSLY DISPLAYED NOTE" was never going to fit.
- **One overlay per *program*, not per key set.** `EDT` and `EVE-EDT` are
  separate entries precisely because they disagree.
- Overlays never change what is transmitted. They are documentation, exactly as
  the second legend on a real DEC keycap was.

---

## Adding keys

```json
{ "label": "Do", "row": 2, "col": 2, "span": 2, "dark": true, "bytes": "\\e[29~" }
```

`row`/`col` place it on the grid; `span` and `rowspan` make it wide or tall
(`0` is double-wide, `Enter` double-high). `dark` is the darker grey DEC moulded
the function row and editing keypad in. `conv` marks a key that is **not** LK201
hardware — a convenience like `^Z` — and tints it teal so the panel never claims
to be reproducing something it isn't.

Escapes in `bytes`: `\e` ESC, `\r` CR, `\n` LF, `\t` TAB, `\cX` Ctrl-X, `\\`.

**Do not add keys that cannot be sent.** On a DEC terminal these are *local* —
the firmware acts on them and transmits nothing at all:

- **F1–F5** (Hold Screen, Print Screen, Set-Up, Session, Break)
- **Compose** and **Lock** (`LK201_SK_META`, `LK201_SK_LOCK` — each has its own
  LED; they travel keyboard→terminal, never to the host)

A button for any of these would be a lie. If asked for one, explain why instead.

---

## Verifying

Two independent checks, and you should use both:

**What the app intends to send.** Launch with
`open --stderr /tmp/deckeys.log DECkeys.app` and read the `bytes:` line — a hex
dump of every key. `^Z=[1a]` proves the profile parsed correctly.

**What actually arrives.** Run `cat -v` in the target and click. `^[OP` is PF1.
This is the only real ground truth, and it distinguishes the two failure modes —
wrong bytes generated, versus right bytes delivered wrongly. Three separate bugs
in this project were the *second* kind, and the hex dump exists because telling
them apart by guesswork wasted an afternoon.

Test against a real terminal *and* through a VT emulator such as
[ezalb](https://github.com/tenox7/ezalb) if you can. Escape sequences pass
through an emulated terminal to the guest behind it, which is a useful proof
that the panel is producing genuine terminal input rather than something that
merely works locally.

---

## Working on the Swift

Read the "Notes for anyone hacking on this" section of the README before you
change signing, event posting, or button drawing. Five non-obvious traps live
there, each of which presented as a silent failure: Hardened Runtime killing
event posting, ad-hoc signing dropping the Accessibility grant on every rebuild,
`keyboardSetUnicodeString` losing to the keyboard layout, Control needing to be
genuinely held rather than asserted in flags, and `.rounded` NSButtons ignoring
both `bezelColor` and their own frame height.

The comments in `DECkeys.swift` record *why* each of those is written the way it
is. Preserve that reasoning if you rework the code — every one of them is a
trap somebody will otherwise fall into again.
