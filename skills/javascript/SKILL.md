---
name: javascript
description: >-
  Feedback rules for JavaScript that runs without a build: names, const and
  let, output, decisions, loops, arrays, functions, modules, and the DOM –
  finding, changing and creating elements, events and state. Used for every
  work with .js files.
metadata:
  files: "*.js *.mjs *.cjs"
---

# Best Practices – JavaScript

<!-- Feedback skill of majikmate/course-feedback. No chapter numbers here:
the course rules say from which chapter a topic applies. Explain a rule
only when its topic has been taught. Terms follow MDN. -->

A `.js` file runs as it is, in the browser or in Node.js: there is no build and
no type check. **A type annotation in a `.js` file is a syntax error** that
stops the whole file (the syntax check shows it).

## Variables and Names

- **`const` by default, `let` only when the value changes, never `var`.** Flag
  `let` for values that never change; `const` is also right for objects and
  arrays whose content changes later.
- **English, descriptive camelCase names** for variables, parameters, functions
  and properties: `pricePerPizza`, `isTallEnough`, `createDishItem`. Flag
  German names, one-letter names outside loop counters and names that lie.
  Boolean names read like questions: `isFull`, `hasTicket`.
- `UPPER_SNAKE_CASE` only for a fixed literal value that is shared across
  modules, a constant like π, or an identifier (`const STORAGE_KEY = "plan";`);
  every other `const` is camelCase. A name in the wrong case is a hint, never a
  mistake.
- Named values instead of repeated magic numbers; values are calculated, not
  typed in.

## Output, Decisions and Loops

- **Template literals** for every text that mixes text and values; flag
  `"Age: " + age` chains.
- `===` and `!==`, never `==` / `!=`; `if (isReady)` instead of
  `if (isReady === true)`.
- No redundant conditions in `else if` chains; the last case is a plain `else`.
- Braces `{ }` for every `if`, `else`, `for` and `while` block.
- `for … of` when only the values matter; an array method (`map`, `filter`,
  `find`, `some`, `reduce`) is equally correct where it fits.
- No code copied several times where a loop or a function would do.
- No leftover `console.log` debugging output in a page; no commented-out code.

## Functions and Modules

- Functions that calculate **return** their result; parameters instead of outer
  variables. Arrow functions with an implicit return for one-expression bodies;
  a function passed as a value is passed **without** brackets.
- Functions at the top, the main program below.
- **Modules**: `<script type="module" src="main.js">`; imports at the top with
  `./` and the file extension (`import { dishes } from "./dishes.js";`); a
  module exports only what other files need and does nothing visible on import.

## Finding Elements

- `document.querySelector()` returns the first match or **`null`**: every
  element is checked for `null` before it is used – an `if (… === null)` check
  or a helper such as `getElement(selector)` that throws an `Error` with the
  selector in the message.
  - ❌ `document.querySelector("#menu").append(item);`
  - ✅ `const menu = getElement("#menu");`
- `querySelectorAll()` returns a list that is empty when nothing matches –
  never `null`. `?.` and `??` only for reading, never to hide a missing element
  that the page needs.
- Each element is looked up once, at the start, and stored in a `const`.

## Changing and Creating Elements

- **`textContent` for text.** `innerHTML` with data from a variable is always a
  finding: the data is read as HTML, which breaks the page for a `<` in a text
  and lets foreign HTML in.
- `classList.add`, `remove` and `toggle` with the class name without a dot;
  the looks stay in the CSS – no `style` changes for what a class can do.
- Attributes as DOM properties: `className`, `htmlFor`, `src`, `alt`,
  `disabled`.
- New elements with `document.createElement()`, filled with `textContent`,
  classes and properties, then added with `append()`. One function per kind of
  element creates it and returns it (`createDishItem(dish)`); the caller
  appends it.
- A list that is built again is emptied first with `replaceChildren()`.

## Events and State

- **`addEventListener`** with the function, not with a call:
  `button.addEventListener("click", handleClick)`; never `handleClick()` and
  never an `onclick` attribute in the HTML.
- `<button type="button">` for a button of the program, `type="submit"` for the
  button that sends a form.
- A form listens to `submit` (not to `click` of its button) and calls
  `event.preventDefault()` first. `value` of a field is always a string:
  `trim()` before an empty check, `Number()` and `Number.isNaN()` for numbers.
- **State and one `update()`**: the data that changes through events lives in
  state variables. Listeners change only the state and then call `update()`;
  `update()` is the only function that writes the state to the page. Values
  that can be calculated from the state are calculated in `update()`, not
  stored.
- A list in state changes through new arrays: `[...items, item]` to add,
  `filter` to remove, `map` to change one item; each item has an `id`.

## Elements as Data and Recursion

- An element described as data is a plain object
  `{ type, props: { ...props, children } }`, made by one `createElement`
  function, not written by hand again and again.
- A recursive function has a **base case** (a text or a number) and a
  **recursive case** that calls itself with a **smaller problem** (each child,
  not the element itself). Props are set as DOM properties; a prop that starts
  with `on` becomes an event listener.
