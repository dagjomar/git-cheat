# Ideas Backlog

Future ideas / notes that we don't want to lose, but aren't ready to act on.

## Category tags for grouped sub-sections

**Idea:** Allow a category tag inside the `# cheat:` marker so the renderer can
auto-create grouped sub-sections (like "Daily", "Branch Stacking", "Bisecting"
on the printed paper version), with a category title and the matching aliases
listed underneath.

**Sketch of syntax:**

```ini
[alias]
    # cheat[Daily]: checkout main
    chkm = checkout main

    # cheat[Branch Stacking]: create a new branch off main
    cbm = "!f() { git switch -c \"$1\" main; }; f"

    # cheat[Bisecting]: start bisect with known good/bad refs
    bisect-start = ...
```

The HTML renderer would then group aliases by category within each source
section, producing the same multi-card layout as the existing printed sheet.
Terminal renderer could indent or print a sub-heading per category.

**Open questions:**
- How should categories work across sources? Merge cross-source categories into
  one "Daily" group, or keep categories scoped per source so a project repo's
  "Daily" stays separate from the global one?
- What's the fallback for aliases without a category — bucket them under
  "General", or just render them above the categorised ones?
- Should category names be case-insensitive / normalised for matching?
