---
name: tutorial-documentation
description: Use this skill when working on Skyline tutorials or tutorial tests.
---

# Skyline Tutorial Documentation

## Essential Reading

Before working on tutorials, read:

1. **ai/docs/tutorial-test-authoring-guide.md** - Tutorial lifecycle (draft, published, translated) and the
   rules every tutorial test follows. Before creating or renaming a tutorial test:
   only a published tutorial's test ends in `Tutorial` (drafts end in `TutorialDraft`), and an
   untranslated tutorial's test starts with `if (IsTranslationRequired) return;`
2. **ai/docs/tutorial-doc-style-guide.md** - Complete style guide for tutorial HTML, screenshots, and test patterns
3. **ai/docs/build-and-test-guide.md** - Building and running tutorial tests

## File Locations

- **Tutorials**: `pwiz_tools/Skyline/Documentation/Tutorials/{TutorialName}/{language}/`
- **Tutorial tests**: `pwiz_tools/Skyline/TestTutorial/`
- **Shared CSS/JS**: `pwiz_tools/Skyline/Documentation/Tutorials/shared/`

Languages: `en`, `ja`, `zh-CHS`

## Quick Reference

- All user actions must be bulleted
- Use "you" not "we"
- Menu pattern: `On the <b>File</b> menu, click <b>Open</b>.`
- Nested menus: `choose <b>X</b>, and click <b>Y</b>`
- Prefer graph-only screenshots when text focuses on the graph
