---
name: typescript
description: >-
  Feedback rules for TypeScript code: names, const and let, output, decisions,
  input, loops, arrays, objects, JSON, modules, functions and structure. Used
  for every work with .ts files.
metadata:
  files: "*.ts *.tsx *.mts"
---

# Best Practices – TypeScript

<!-- Feedback skill of majikmate/course-feedback. No chapter numbers here:
the course rules say from which chapter a topic applies. Explain a rule
only when its topic has been taught. -->

## Variables and Names

- **`const` by default, `let` only when the value changes, never `var`.** Flag
  `let` for values that never change. `const` is the default for every variable
  that gets no new value – also for objects and arrays whose content changes
  later.
- **English, descriptive camelCase names** for variables (also `const`
  variables), parameters, functions, properties (also `readonly` properties) and
  methods: `pricePerPizza`, `isTallEnough`, `rollDie`. Flag German names
  (`preis`, `istFertig`), one-letter names outside loop counters (`i`, `j`) and
  names that lie (`sum` holding an average).
- Boolean names read like questions: `isHot`, `hasTicket`, `canRide`.
- **`UPPER_SNAKE_CASE` only for real constants.** A real constant is a fixed
  value written as a literal (a number, a string or a boolean) that is one of
  these:
  - **Shared across modules** – it is exported, or it is a public
    `static readonly` class member that other files read:
    `export const MAX_PLAYERS = 4;`, `static readonly MAX_LEVEL = 50;` (read as
    `Player.MAX_LEVEL`).
  - **A constant like PI** – fixed by nature or by definition, never a setting
    of the program: `const PI = 3.14159;`, `const SECONDS_PER_MINUTE = 60;`,
    `const DAYS_PER_WEEK = 7;`. Also when it is used in one module only.
  - **An identifier** – a fixed name, key, file name or address that the program
    uses to find something: `const SCORES_FILE = "scores.json";`,
    `const STORAGE_KEY = "high-scores";`. Also when it is used in one module
    only.
- **Every other `const` variable is camelCase**: calculated values
  (`const total = pizzas * price;`), objects, arrays and class instances
  (`const player = new Player("Mia");`, `const scores: number[] = [];`), and
  fixed values that are only a setting of this program and are used in one
  module (`const pricePerPizza = 9.5;`, `const maxAttempts = 3;`). A
  `private static readonly` member that only its own class uses follows the same
  rule.
- **An object constant used as an enum is PascalCase**, named like its type:
  `const Direction = { Up: "Up", Down: "Down" } as const;` with
  `type Direction = (typeof Direction)[keyof typeof Direction];`.
- A name in the wrong case is a hint, never a mistake. When it is not clear
  whether a value is a real constant, accept both cases.
- Named values instead of repeated magic numbers (`const maxAttempts = 3;`,
  `const DAYS_PER_WEEK = 7;`).
- Values are **calculated**, not typed in: `const total = pizzas * price`, not
  `const total = 28.5`.

## Output

- **Template literals** for every output that mixes text and values; flag
  `"Age: " + age + " years"` chains.
- Money and averages rounded for printing (`toFixed`), units in the message.
- No leftover debugging output.

## Decisions and Logic

- `===` and `!==`, never `==` / `!=`.
- `if (isReady)` instead of `if (isReady === true)`; `!flag` instead of
  `flag === false`.
- **No redundant conditions in `else if` chains**: after `if (x >= 90)`, the
  next branch needs only `x >= 75`, not `x >= 75 && x < 90`. The final case is a
  plain `else`.
- Range checks as `x >= 1 && x <= 5`; `x === 1 || x === 2` instead of
  `x === 1 || 2`.
- Braces `{ }` for every `if`, `else`, `for` and `while` block, even for single
  statements.
- Result variables declared with `let` **before** a decision and assigned inside
  it – not declared inside the blocks.

## Input

- `prompt()` results converted with `Number()` before calculating; text kept
  with `?? ""`.
- Invalid input handled where the README asks for it (`Number.isNaN`, empty
  string, ranges); checks come before the normal case.
- `age === NaN` is a bug – point to `Number.isNaN()`.

## Loops and Arrays

- Accumulators declared **before** the loop.
- `for … of` when only values matter; the index loop when positions matter;
  `i < array.length`, not `<=`.
- Sums, maxima and searches may use a loop **or** an array method (`reduce`,
  `find`, `some`) – both are correct.
- No code copied several times where a loop or a function would do.
- Arrays typed when created empty (`const drawn: number[] = []`).
- Random values stored in a `const` variable before they are printed and
  compared.

## Objects, JSON and Modules

- Values that belong together live in one object with a declared `type`
  (capitalised name), not in parallel arrays; arrays of objects are typed
  (`Song[]`).
- The result of `JSON.parse()` gets a type annotation;
  `JSON.stringify(x, null, 2)` for readable output; file paths are relative to
  the program.
- Modules export only what other files need and contain no `console.log` or
  `prompt()` that runs on import; imports stand at the top, JSR imports before
  own files, paths with `./` and `.ts`.

## Type Stripping

Type stripping (Node.js with `node main.ts`, Vite) only removes the types. Some
forms of TypeScript create JavaScript code, so type stripping cannot run them:
an `enum`, a parameter property (`constructor(private name: string)`), a
`namespace` with code. They are correct TypeScript and never lower the score.
Handle all of them in the same way:

- **Before the chapter that teaches the form** (in a course that does not teach
  it: always), give one short hint under Best Practices that does not explain
  type stripping. It always has the same sentences; for an `enum`:

  > You use an `enum` (`Direction`). This is correct TypeScript, and your
  > program works. But it is not compatible with type stripping, a concept we
  > explain in more detail in chapter N. That is why an object constant is
  > normally recommended:

  For another form, only the form and the recommended form change. Then show the
  recommended form with the student's names. When the course has not taught the
  recommended form by the assignment's chapter, leave out the last sentence and
  the code: the hint ends after "in chapter N". N is the chapter that the course
  rules name for type stripping; without one, write "in a later course" instead
  of "in chapter N".

- **The recommended forms:** for an `enum`, an object constant with a type of
  the same name, `const Direction = { Up: "Up", Down: "Down" } as const;` with
  `type Direction = (typeof Direction)[keyof typeof Direction];`; for a
  parameter property, the long form (the field declared in the class, assigned
  in the constructor); for a `namespace`, a module of its own.
- **From the chapter that teaches the form on**, accept it without a comment.
- **In a project that only allows erasable syntax** (a Vite project), these
  forms fail the build with TS1294, a failed type check: show the recommended
  form next to the student's code and, when the course has the TypeScript
  Essentials, name topic 18, TypeScript in Vite Projects.
- **`import` and `import type` are both correct for a type**: in a program that
  runs with `ts`, accept `import { Song }` and `import type { Song }` without a
  comment. In a Vite project, a type imported without `type` fails the build
  with TS1484, a failed type check: show `import type` next to the student's
  import and name topic 18 as above.

## Functions and Methods

- Explicit types for every parameter and return type; `void` for functions that
  return nothing. No `any`; no non-null assertion `!` without a reason.
- Functions that calculate **return** their result; printing happens in the main
  program.
- Parameters instead of outer variables; no duplicated logic across functions.
- Arrow functions with implicit return for one-expression bodies; a function
  passed as a value is passed **without** brackets.
- Array methods (`map`, `filter`, `find`, …) for transformations and selections;
  `find` results checked for `undefined`.

## Structure and Formatting

- Functions at the top, the main program below; data, logic and main program in
  separate modules where the README asks for it.
- Short comments only where the code cannot explain itself; no commented-out
  code.
- Prettier formatting (the editor formats on save); the Problems panel shows no
  errors – the type check passes.
