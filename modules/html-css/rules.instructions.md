---
applyTo: "**/FEEDBACK.md"
---

# Best Practices – HTML and CSS

<!-- Module "html-css" of majikmate/course-feedback, copied into the course as
best-practices-html-css.instructions.md. No chapter numbers here: the course file
says from which chapter a topic applies. Explain a rule only when its topic has
been taught. -->

## Selectors – Use the Right Tool

- **Element selectors** (`p`, `h1`, `a`) for the _default look_ of an element
  type across the whole page (base typography, link colour, resets).
- **Class selectors** (`.card`, `.nav-link`) for _reusable components and
  variations_. Classes are the default choice for styling.
- **ID selectors** (`#main-navigation`) only for _one single element_ per page,
  and preferably **not for styling** at all: ids are for anchors
  (`href="#contact"`), labels (`for="email"`) and JavaScript. Styling with ids
  creates very high specificity that is hard to override later.
  - ❌ `#box1 { ... } #box2 { ... }` with identical declarations → should be one
    class.
  - ❌ The same id used twice in one document → invalid HTML.
  - ✅ `#contact` as a link target plus `.contact-section` for styling.
- **Combinators and grouping**: praise sensible use of descendant (`nav a`),
  child (`ul > li`), grouping (`h1, h2, h3`) and pseudo-classes (`a:hover`,
  `li:first-child`). Flag over-long chains (`body div div ul li a`) – they are
  fragile and too specific.
- **Avoid `!important`.** If it appears, explain which specificity conflict
  caused it and how to resolve it with a better selector.
- **Avoid inline styles** (`style="..."`) and `<style>` blocks when the README
  asks for a separate stylesheet. Inline styles win over every stylesheet rule
  and cannot be reused.
- Flag **duplicated declarations** across several rules → extract a shared class
  or use grouping.

## Class Naming

- **English words only**, lowercase, **kebab-case** (`main-navigation`,
  `product-card`). Flag German or mixed-language names (`.ueberschrift`,
  `.navLeiste`, `.rot`), camelCase and spaces.
- Names describe **purpose or role**, not appearance:
  - ❌ `.red`, `.big-text`, `.left-box`, `.div1`, `.box2`, `.style3`
  - ✅ `.warning`, `.page-title`, `.sidebar`, `.card`, `.price`
  - Exception: tiny utility classes are acceptable if used consistently.
- Related elements share a naming pattern (`.card`, `.card-title`,
  `.card-image`). BEM-style `card__title` is fine too; just be consistent.

## English Everywhere in the Source

- Class names, ids, file names, CSS custom properties (`--brand-color`), code
  comments and `alt` texts describing images: **English**.
- The **visible page content** may be in any language the README allows.
- Flag German identifiers politely and give the English alternative.

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

## CSS Organisation

- Separate `styles.css` (or a similar English file name) linked from the HTML.
- Rules grouped in a logical order (reset/base → layout → components); short
  comments for sections are welcome.
- `rem`/`em` for font sizes and `px` for borders are good practice; both are
  acceptable unless the README prescribes units.
- A `box-sizing: border-box` reset is good practice.
- Repeated colours or spacings → suggest CSS custom properties.
- Layout: positioning only where needed; flexbox or grid for layout. Do not
  penalise flexbox or grid used earlier than taught.
- Responsive: viewport meta present, media queries where the README requires
  them, no fixed widths that break on small screens.
