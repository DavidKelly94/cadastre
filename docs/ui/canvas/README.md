# Design canvas artboards

The source for the VividHome capture-app design canvas. Each `.dc.html` is one
artboard; `canvas.json` places them and names the pages.

**These files are the source, not the canvas.** The canvas itself is assembled
from them into a single page — roughly 2.5 MB, almost all of it the editor —
which is published rather than committed (`.gitignore`). Re-assembling from a
fresh copy of the editor is how a change reaches the canvas; never hand-edit the
built page.

Changes go one of two ways, and mixing them loses work:

- **Here:** edit the artboards, re-assemble, republish to the same URL.
- **In the canvas:** edits saved there become a new version, and these files are
  then behind. Read the published canvas back out before editing here again.

Content follows `../design-canvas-brief.md`, which is the brief these were drawn
from and the place decisions are recorded. The tokens in the artboards are lifted
from its section 5 and their contrast ratios are computed — do not adjust a
colour here without updating the brief.
