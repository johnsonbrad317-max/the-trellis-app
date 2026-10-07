# The Living Vine — art brief

What this is for: the dashboard of The Trellis shows a vine growing up a wooden
trellis. Today it switches between four whole pictures. The goal is a vine
that changes **piece by piece**: a new Runner sees one shoot climb, branches
bear fruit one at a time as they stay faithful, and a hard stretch withers a
branch or two while the rest stand. For the app to do that, the vine has to be
drawn as **one plant in separate, perfectly aligned layers**. This brief says
exactly what to produce.

---

## The one rule that matters

**Every file is the same canvas, and every branch is in exactly the same place
in every file.** The app stacks these files on top of each other. If a branch
moves even slightly between the "leafed" and "fruiting" versions, it will look
doubled. Everything else is taste; this is the requirement.

The easiest way to guarantee it: draw the whole vine **once** as a vector file
(SVG), organised into named groups, then export each group as its own
transparent PNG from that single master. Do not draw the states separately.

## Canvas and placement

- Canvas: **1696 × 2528 pixels**, portrait, **transparent** background (PNG with
  alpha). This matches `assets/images/trellis_empty.png`, the bare trellis the
  vine sits on. Export at that exact size — no cropping, no margins added.
- The wooden frame occupies the region from (120, 36) to (1578, 2442) on that
  canvas. The vine should grow **up from the bottom rail** (y ≈ 2440) and may
  reach the top rail (y ≈ 40) when fully grown. Leaves may overhang the posts
  slightly; nothing should go off the canvas.
- No trellis, no ground, no shadow, no background in any file. **Vine only.**

## Style

- 19th-century botanical woodcut / copper engraving: fine hatched line work,
  no gradients, no soft shading, no photographic texture.
- Colours: brass-and-bronze inks only — `#B8860B` (antique brass) for lines
  and highlights, deepening to `#5A4A1E` in shadow; sparing `#1E3A2B` (forest
  green) is acceptable for the deepest shadows. Withered parts shift toward a
  dry `#8A7A5A`. No other colours. No pure black.
- It is a **grapevine**: a woody main stem, side branches, broad lobed leaves,
  curling tendrils, and clusters of grapes for fruit.
- Match the existing art in `assets/images/trellis_flourishing.png` for line
  weight and feel.

## Structure: one stem, six branches

Draw one main stem rising from bottom centre, and **six side branches** that
leave it in this order (1 lowest, 6 highest), alternating sides:

| Branch | Leaves the stem at (y) | Side  | Reaches about |
| ------ | ---------------------- | ----- | ------------- |
| 1      | ~2250                  | left  | x 300, y 2050 |
| 2      | ~1950                  | right | x 1400, y 1750 |
| 3      | ~1650                  | left  | x 280, y 1420 |
| 4      | ~1350                  | right | x 1420, y 1120 |
| 5      | ~1050                  | left  | x 320, y 800  |
| 6      | ~750                   | right | x 1380, y 500  |

The stem itself continues to about y 300 above branch 6. Branches may cross
in front of or behind the lattice; it does not matter, because the trellis is
a separate picture underneath.

## The layers to deliver

Export **one transparent PNG per layer**, all 1696 × 2528, named exactly:

**The stem (3 files)** — the main trunk only, no branches:
- `vine_stem_bare.png` — woody stem with small buds, no leaves
- `vine_stem_leafed.png` — the same stem with its leaves and tendrils
- `vine_stem_withered.png` — the same stem, leaves dry and curled

**Each branch (4 files × 6 branches = 24 files)** — branch N and nothing else:
- `vine_branch_N_bare.png` — the woody branch alone, with buds
- `vine_branch_N_leafed.png` — the same branch with leaves and tendrils
- `vine_branch_N_fruiting.png` — the same branch, leafed, **plus** one or two
  grape clusters hanging from it
- `vine_branch_N_withered.png` — the same branch, leaves dry and drooping, no
  fruit (or one shrivelled cluster)

**27 files total.** Each must contain only its own part: the stem file has no
branches; branch 3's files contain nothing of branches 2 or 4.

Within one branch, the four versions must share the **same wood**: the branch
and its sub-twigs in identical positions; only leaves, fruit and condition
change. (In vector terms: duplicate the bare branch group and add to it; never
redraw it.)

## Checks before handing over

1. Open any two files of the same branch over each other at 50% opacity: the
   wood lines up exactly.
2. Open all 27 files over `trellis_empty.png`: it reads as one plant on one
   trellis, nothing floating, nothing doubled.
3. Open `vine_stem_bare.png` alone: it reads as a young vine, a single shoot
   just planted.
4. Open the stem plus branches 1–6 fruiting: it reads as a flourishing vine,
   close to today's `trellis_flourishing.png`.
5. Every file is 1696 × 2528 with a transparent background, and nothing
   touches the canvas edge.
6. Also hand over the master vector file (SVG), so later changes come from the
   same source.

## How the app will use them (for context, not for the artist)

- Branches appear in order 1 → 6 as the Runner's season progresses and they
  keep checking in; the stem alone is day one.
- A branch bears fruit when the Runner's consistency on their rhythms is high;
  the more consistent, the more branches fruit.
- Recent misses or an Anchor Rhythm streak wither one or two branches (the
  newest first); the rest stay as they were.
- Everything animates as a crossfade between a branch's versions, so no file
  needs any motion built in.

---

### Prompt to paste into a design session

> Create a 19th-century botanical woodcut-style grapevine as a single vector
> illustration on a transparent 1696 × 2528 px portrait canvas, drawn in
> antique brass and bronze inks only (#B8860B lines, #5A4A1E shadows), no
> background, no trellis. One woody main stem rises from bottom centre
> (y ≈ 2440) to y ≈ 300, with six side branches leaving it at y ≈ 2250 (left),
> 1950 (right), 1650 (left), 1350 (right), 1050 (left) and 750 (right).
> Organise the file into named groups: `stem_bare`, `stem_leafed`,
> `stem_withered`, and for each branch N = 1…6: `branch_N_bare`,
> `branch_N_leafed`, `branch_N_fruiting` (leafed plus grape clusters) and
> `branch_N_withered` (dry, drooping leaves, no fruit). Within a branch the
> wood must be pixel-identical across its four groups — duplicate the bare
> wood and add leaves or fruit to it; never redraw it. Export every group as
> its own transparent PNG at full canvas size, named `vine_stem_bare.png`,
> `vine_branch_3_fruiting.png`, and so on — 27 files — plus the master SVG.

---

## Revision 2 — technical notes to keep the second pass drop-in

(Added after the first delivery, alongside the owner's art direction: larger,
denser vine; fine hatching over parchment; muted antique spot colour;
exaggerated withered shapes.)

1. **Keep everything that made pass one work.** Same 27 file names, same
   1696 × 2528 transparent canvas, same stacking (stem, then branch 1 … 6),
   same attachment heights (2250, 1950, 1650, 1350, 1050, 750), and wood that
   is identical across a part's states. Branches may reach much further and
   overlap one another — each file still holds only its own part.
2. **The opaque base colour is `#F8F1E0`** (the app's vellum — the card the
   vine sits on), not `#F9F6F0`. The trellis shows the card through its
   lattice, so a fill in any other colour reads as a patch.
3. **Exact inks:** wood `#B8860B` brass with `#5A4A1E` bronze shadow; leaves
   a muted green `#4F6B4A` deepening to forest `#1E3A2B`; grapes a muted
   purple `#6B3A55` deepening to `#3A1E2E`; withered parts scorched umber
   `#7A5A22` deepening to `#4A3414`. No pure black, no white.
4. **Hatching must survive being small.** The dashboard shows the whole
   canvas about 280 points tall (≈ ⅓ size on a phone) and the Cloud roster
   about 40 points. Keep hatch lines at least ~4 px wide and ~6 px apart on
   the 1696-wide canvas, matching the weight of the lines in
   `trellis_empty.png`; finer work turns to grey mush or moiré.
5. **Colour is final in the art.** The app will show the files exactly as
   drawn (no tinting), so what you see over `trellis_empty.png` on a
   `#F8F1E0` background is what the Runner sees.
6. **Check before handing over:** all 27 over `trellis_empty.png` on
   `#F8F1E0` — the fully grown, all-fruiting vine should cover most of the
   lattice; withered branches should be recognisable at a glance even at a
   third of the size.
