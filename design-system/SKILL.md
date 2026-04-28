# SKILL: Designing for VOLTRA Live

When a user asks for a new screen, sheet, or feature for **VOLTRA Live**, follow this skill.

## Read first, in this order

1. `design-system/README.md` — content + visual fundamentals.
2. `design-system/colors_and_type.css` — every token, named.
3. `design-system/ui-kit.html` — every existing component rendered.
4. The relevant `VoltraLive/Views/*.swift` view file. The Swift source is the source of truth.
5. `AGENTS.md` (repo root) — sacred files, control-write policy, ship process.

If the request touches the BLE protocol, **stop and re-read** the "Sacred files" section of `AGENTS.md`. The design system has nothing to say about wire format and you should not invent any.

## The mental model

VOLTRA Live is a **rack-mounted instrument**, not an app. A user is mid-set, sweating, looking at the screen for ≤ 1 second between reps. Every design decision serves that: big mono numerals, single accent color, flat surfaces with hairline borders, no decorative motion.

When you catch yourself reaching for a gradient, a shadow, an emoji, an icon-without-a-label, a 13-px secondary metric, or a "Great set!" toast — stop. That's a different app.

## Hard rules

These are non-negotiable. If a user request implies breaking one, surface the conflict before coding.

1. **Dark canvas only.** No light-mode variant. Background is `--vl-bg` (`#0a0e0c`).
2. **One accent color.** `--vl-accent` (`#00d4aa`). Phase colors are semantic, not decorative.
3. **All live numbers are mono + tabular.** Never proportional digits on a readout.
4. **Tile radius is 18px. Button radius is 12px.** Don't invent a third radius.
5. **Tap targets ≥ 44px.** Primary CTAs 50px. Tile tap zones 56px.
6. **At most 4 primary tiles per live screen.** If you need a 5th, remove one first.
7. **No drop shadows on tiles. No gradients on canvas.** A 1px hairline (`--vl-border`) is the only edge treatment.
8. **No emoji. No exclamation marks. No motivational copy.** Operator voice.
9. **Every icon has a label next to it.** Icons never carry semantic load alone.
10. **Use the names in `README.md → CONTENT FUNDAMENTALS → Naming the things on screen`.** REP / SET / PULL / RETURN / TRANSITION / REST are reserved terms.

## How to compose a new screen

1. **Pick the surface.** Full screen? `--vl-bg`. Sheet? `--vl-bg-elev` with a top hairline. Inside a tile? `--vl-bg-elev-2`.
2. **Pick the layout.**
   - Live data → 2×2 tile grid (REPS, PHASE, FORCE, REST), 12px gap.
   - Connect / setup → centered card on canvas, 40px interior padding.
   - List of items → full-width rows, 14px padding, hairline divider between.
   - Settings / detail → grouped sections with 11px UPPERCASE label + tile group.
3. **Pick the type.** Pull from the ramp in `colors_and_type.css`. Don't invent sizes.
4. **Render in the UI kit first.** Add your new component as a card in `design-system/ui-kit.html` before wiring it into a view. If it doesn't look right standalone, it won't look right in context.

## Variations and tweaks

When the user asks for "a few options" or "explore some directions":

- Vary **layout, density, and information hierarchy** — what's primary vs secondary, 2-up vs 4-up tiles, chart-prominent vs number-prominent.
- Don't vary **color palette, type stack, radius, or surface elevations.** Those are the design system; varying them produces "VOLTRA Live but in a different brand", which isn't useful.
- Expose variations via Tweaks (toggle/radio) when prototyping in HTML.

## Before you finish

- [ ] Numbers are mono + tabular?
- [ ] Tap targets meet the floor?
- [ ] Used existing components from the UI kit, or added the new one to it?
- [ ] Copy follows the operator voice and reserved terminology?
- [ ] No emoji, no exclamation marks, no motivational fluff?
- [ ] Updated `design-system/colors_and_type.css` if you introduced a new token?
- [ ] Updated `design-system/README.md` and `WORK_LOG.md` if behavior changed?
