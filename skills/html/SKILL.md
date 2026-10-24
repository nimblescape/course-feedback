---
name: html
description: >-
  Feedback rules for HTML pages: document skeleton, semantic elements, valid
  nesting, class and id names, English in the source. Use for every student work
  with .html files.
metadata:
  files: "*.html *.htm"
---

# Best Practices – HTML

<!-- Feedback skill of majikmate/course-feedback. No chapter numbers here:
the course rules say from which chapter a topic applies. Explain a rule
only when its topic has been taught. -->

## Semantic HTML and Validity

- Correct document skeleton: `<!DOCTYPE html>`, `<html lang="…">`, `<head>` with
  `<meta charset="UTF-8">`, viewport meta, `<title>`, external stylesheet linked
  with `<link rel="stylesheet" href="…">`.
- Landmarks instead of generic `<div>` where meaning exists: `<header>`,
  `<nav>`, `<main>`, `<section>`, `<article>`, `<aside>`, `<footer>`.
- One `<h1>` per page, heading levels in order (no jump from `h1` to `h4`).
- Lists for lists (`<ul>`/`<ol>`), `<a>` for links, `<button>` for actions,
  `<img>` with a meaningful `alt`, `<figure>`/`<figcaption>` for captioned
  images, `<table>` only for tabular data.
- Valid nesting (no `<div>` inside `<p>`, no block elements inside `<a>` unless
  HTML5 allows it), all tags closed, attribute values quoted.
- **Valid means: HTML-validate reports no errors** (presets
  `html-validate:recommended` and `html-validate:prettier`).
- Flag "div soup": more than two nested `<div>` wrappers without a reason.
- **Avoid inline styles** (`style="..."`) and `<style>` blocks when the README
  asks for a separate stylesheet. Inline styles win over every stylesheet rule
  and cannot be reused.

## Ids

- An id names **one single element** per page. Ids are for anchors
  (`href="#contact"`), labels (`for="email"`) and JavaScript.
  - ❌ The same id used twice in one document → invalid HTML.
  - ✅ `id="contact"` as a link target.

## Class and Id Names

- **English words only**, lowercase, **kebab-case** (`main-navigation`,
  `product-card`). Flag German or mixed-language names (`ueberschrift`,
  `navLeiste`, `rot`), camelCase and spaces.
- Names describe **purpose or role**, not appearance:
  - ❌ `red`, `big-text`, `left-box`, `div1`, `box2`, `style3`
  - ✅ `warning`, `page-title`, `sidebar`, `card`, `price`
  - Exception: tiny utility classes are acceptable if used consistently.
- Related elements share a naming pattern (`card`, `card-title`, `card-image`).
  BEM-style `card__title` is fine too; just be consistent.

## English Everywhere in the Source

- Class names, ids, file names, code comments and `alt` texts describing images:
  **English**.
- The **visible page content** may be in any language the README allows.
- Flag German identifiers politely and give the English alternative.
