---
name: react
description: >-
  Feedback rules for React with TypeScript: components and props, JSX, lists
  and keys, state and events, forms, sharing state, effects and data, and React
  Router. Used for every work with a file that imports React.
metadata:
  files: "*.tsx *.jsx *.ts *.mts *.js *.mjs"
  contains: '\bfrom\s*["''](react|react-dom)(/[\w./-]*)?["'']'
---

# Best Practices – React

<!-- Feedback skill of majikmate/course-feedback. No chapter numbers here:
the course rules say from which chapter a topic applies. Explain a rule
only when its topic has been taught. Terms follow react.dev; JavaScript,
HTML and CSS terms follow MDN. -->

The rules of the TypeScript skill apply to the code of a React project too.
This skill adds the rules of React.

## Components

- A component is a function with a **PascalCase** name that returns JSX and is
  used as a tag: `<SongCard />`, never called as a function (`{SongCard()}`).
  `export function SongCard(…)` and an arrow function
  (`export const SongCard = (…) => …`) are both correct.
- **One component per file** with a named export; the file name is kebab-case
  and matches the component (`song-card.tsx` exports `SongCard`). Data, types
  and helper functions without JSX live in `.ts` modules.
- A component is defined at the **top level** of a module, never inside
  another component: a component defined in a component is a new type in every
  render, so React throws its DOM elements and its state away each time.
- Components are **pure**: during the render they only calculate JSX from their
  props and state. They change no variable outside themselves, call no setter,
  start no request and do not navigate. Such work belongs in an event handler or
  in an effect.
- React owns the page: no `document.querySelector`, `classList`, `textContent`
  or `append` in a component. The page changes through state and JSX. Only
  `src/main.tsx` reads the root element (with a `null` check) for `createRoot`.
- Repeated JSX with different data becomes a component with props; a component
  with many jobs is split into smaller components.

## Props

- The props have a **type above the component**, named after it:
  `type SongCardProps = { title: string; minutes?: number };`. The props are
  **destructured in the parameter list**:
  `export function SongCard({ title, minutes = 3 }: SongCardProps)`. Optional
  props have `?` and, where needed, a default value in the destructuring.
- Content between the tags arrives as `children` with the type `ReactNode`.
- Props are **read-only**: never assign to a prop and never change an array or
  an object that came as a prop.
- `key` is not a prop: the child cannot read it.
- A component needs no return type; every other function has one (TypeScript
  skill). A function that builds elements with `createElement` returns
  `ReactElement`.

## JSX

- JSX uses the **DOM property names**: `className`, `htmlFor`, `tabIndex`,
  `maxLength`; every hyphenated attribute name is camelCase, except `aria-…`
  and `data-…`. Every element is closed (`<img … />`, `<br />`).
- **One expression** in braces: `{a ? b : c}` for one of two, `{condition && b}`
  only with a real boolean condition (`{songs.length > 0 && …}`, never
  `{songs.length && …}`, which shows `0`), `{value ?? "default"}` for `null` and
  `undefined`. Decisions with `if` and loops happen above the `return`, not in
  the braces.
- A fragment `<>…</>` groups elements without an extra `<div>`.
- Text from the data goes into braces as text; `dangerouslySetInnerHTML` with
  data is always a finding (like `innerHTML`).
- **Looks in classes**: `className`, with the given CSS or with Tailwind CSS.
  `style={{ … }}` only for values that come from the data (a width in
  percent). With Tailwind CSS, every class name is complete in the code: no
  class names put together from parts (`` `bg-${colour}-600` ``), because
  Tailwind CSS creates no rule for them.
- `<button type="button">` for every button that does not send a form.

## Events

- An event handler is passed as a **function, not called**:
  `onClick={handleAdd}`. `onClick={handleAdd()}` calls it during the render.
  An arrow function passes an argument: `onClick={() => onSelect(song.id)}`.
- Handlers inside a component are named `handleX` (`handleAdd`,
  `handleSubmit`); callback props are named `onX` (`onSelect`, `onAdd`).

## Lists and Keys

- A list is built with `map()`. The element that `map()` returns carries a
  **`key`** that is **stable and unique** among its siblings: the `id` from the
  data. The array index is no key for a list that changes (add, remove, sort,
  filter); `Math.random()` or `crypto.randomUUID()` in the render is never a
  key.
- A filtered or sorted list is calculated with `filter` and `toSorted`; `sort`
  and `reverse` change the array itself and are never used on props or state.

## State

- `useState` for every value that changes through events and changes the page; a
  normal variable does not render again. The state has a type where it cannot
  be inferred: `useState<Song | null>(null)`, `useState<Task[]>([])`.
- **Hooks only at the top level** of a component (or of a custom hook whose
  name starts with `use`): never in an `if`, a loop, a handler or a nested
  function, and never in a normal function.
- **State is a snapshot**: after `setCount(count + 1)`, `count` keeps its old
  value until the next render. A new value that depends on the old one uses an
  **updater function**: `setCount((c) => c + 1)`, required when several updates
  happen in one handler.
- **Never change state**: no `push`, `splice`, `sort`, `reverse` and no
  assignment to a property (`task.done = true`) on a state value. A change
  creates a new array or object: `[...tasks, task]`, `filter` to remove, `map`
  with `{ ...task, done: true }` to change one item.
- **Minimal state**: a value that can be calculated from props or state
  (counts, totals, filtered and sorted lists, a text built from state) is
  calculated during the render, not stored in a second state and not updated by
  an effect. A selection stores the `id`, not a copy of the item.
- A union type for related states instead of several booleans:
  `{ status: "loading" } | { status: "error"; message: string } | { status: "done"; songs: Song[] }`;
  the code checks `status` before it reads the data.

## Forms

- **Controlled inputs**: `value` (or `checked` for a checkbox) from state and
  `onChange` that sets the state. An input with `value` but without `onChange`
  cannot be changed.
- `event.target.value` is always a string: `Number()` for a number, a check of
  the allowed values for a union type, `trim()` before a text is checked for
  being empty.
- The form handles `onSubmit` (not `onClick` of the button) and calls
  `event.preventDefault()` first; its button is `type="submit"`. Every input has
  a `<label>` with `htmlFor`, or is inside its label.

## Sharing State

- **One owner per value**: when two components need the same value, the state
  lives in their closest common parent. Values go down as props; changes go up
  as calls of callback props (`onSelect(song.id)`). The same data never lives
  in the state of a child and of its parent.
- A child that only shows a value gets it as a prop, not as its own state that
  copies the prop.

## Effects and Data

- `useEffect` only to **synchronise with something outside React**: a request,
  a timer, a subscription, the title of the document. Not for values that can be
  calculated during the render, and not for the reaction to an event: that
  belongs in the event handler.
- The **dependency array** lists every value of the component that the effect
  reads: `[]` runs it after the first render only, `[artist]` also when
  `artist` changes. An effect without an array that calls a setter starts a
  request in every render – an endless loop.
- The effect function is not `async`: it defines an `async` function and calls
  it. A **cleanup** stops what the effect started: an `ignore` flag so that an
  old answer sets no state, `clearInterval`, `removeEventListener`.
- A request checks `response.ok` (a `404` does not reject), catches errors with
  `try … catch` and shows every state: loading, error with the message
  (`error instanceof Error ? error.message : String(error)`) and the data. The
  result of `response.json()` gets a type.
- In development, `StrictMode` renders twice and runs every effect twice: two
  requests in the Network panel are no mistake.

## React Router

- `BrowserRouter` wraps the app once, in `src/main.tsx`; `Routes` with one
  `Route` per page, and `path="*"` for a page that does not exist.
- **Every link inside the app is a `Link` or a `NavLink`**: an `<a href>` loads
  a new document, and all state starts again. `<a>` stays for links to other
  sites. `NavLink` marks the open page.
- A value of `useParams()` is a `string` or `undefined`: check it and convert it
  (`Number(id)`); an unknown id shows a "not found" message instead of a crash.
- `useNavigate()` returns `navigate`, which is called in a handler after an
  action (a sent form), never during the render.
- A value that must stay when the page changes lives in the component around
  `Routes` and goes down through `element={<Page … />}`.

## Without JSX (`createElement`)

- `createElement(type, props, ...children)` from `react`, `null` when there are
  no props, `...array.map(…)` for a list of children; `createRoot` from
  `react-dom/client`.
- `createRoot` is called **once**, after the `null` check of the container;
  every update only calls `root.render(…)` – no `replaceChildren()` or other
  DOM changes by hand.

## Structure

- `src/main.tsx` creates the root once and renders `<App />` inside
  `<StrictMode>`. `App` holds the state of the app or the routes.
- Imports at the top with the file extension (`./song-card.tsx`, `./songs.ts`);
  types with `import type` in a Vite project (TypeScript skill).
- No leftover `console.log` and no commented-out code. `npm run build` reports
  no error.
