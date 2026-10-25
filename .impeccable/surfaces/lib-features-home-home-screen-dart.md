---
version: 1
slug: "lib-features-home-home-screen-dart"
primary_target: "lib/features/home/home_screen.dart"
related_targets: ["lib/features/history/history_screen.dart","lib/features/settings/settings_screen.dart"]
---

# Surface brief: Heisenbudget app (all screens)

Scope: native app UI (Flutter, Android + iOS), mode Operate. Product truth: extra/PRODUCT.md. Plan: extra/UI_OVERHAUL_PLAN.md.
Audience and job: one person logging and reviewing their own money, in brief one-handed sessions, mostly in dim light. Success: logging takes seconds and the numbers are instantly legible.
Selected direction: Instrument Readout (user-chosen). One identity on both OSes, dark-first, "Bench" light sibling, switchable Lab flavor layer.
Unresolved by design: budgets (Part 3 of the plan, not built).

## Direction contract

THESIS: Money is a measurement. The app is a calm bench instrument: ruled readouts, tick scales, one spectrum chart. It refuses stat cards, pill buttons, donut charts, shadows and glow-everywhere neon; depth comes from hairlines and tonal panels.

OWN-WORLD: Ink-black ground with a faint green cast (#070A09), tonal panels, 1dp hairlines, no shadows. Received green and Spent amber are two fixed "channels"; one switchable accent (default Assay green) is only chrome. Geist for text (Inter, Atkinson Hyperlegible, System selectable), Geist Mono tabular for every number. Small radii (8 to 12), outlined icon squares, tracked uppercase 12sp section labels, dotted-leader ledger rows. Graticule only inside the chart; tick ruler only on the period control.

STORY: The user sees what they have, what came in and went out for the chosen period, and where spending concentrates, then logs the next transaction with one tap. They believe the numbers because they are precise and aligned; the wink (PURITY, flat-line wording) never slows the task.

FIRST VIEWPORT: Home on a 360x800dp phone. Top: tracked HEISENBUDGET label. Balance in 44sp Geist Mono, left aligned; beneath it one caption row with BALANCE and PURITY. Period control with dropdown, arrows and a tick ruler below. Three dotted-leader ruled rows RECEIVED / SPENT / NET with right-aligned mono amounts. The spectrum chart (top 5 categories as amber peaks with icons and percentages) fills the middle. Recent ledger below. The square-cornered + LOG key sits bottom right above a slim hairline-topped tab bar.

FORM: Instrument readout, position 1 on the ordered grounded list (the pick card, chosen by the user); seed key b1953fb5.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
