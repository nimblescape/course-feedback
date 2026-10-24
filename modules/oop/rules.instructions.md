---
applyTo: "**/FEEDBACK.md"
---

# Best Practices – Object-Oriented Programming in TypeScript

<!-- Module "oop" of majikmate/course-feedback, copied into the course as
best-practices-oop.instructions.md. No chapter numbers here: the course file
says from which chapter a topic applies. Explain a rule only when its topic has
been taught. -->

This module describes the long, explicit form. Where the course file accepts
TypeScript shorthands – parameter properties, `get`/`set` accessors, `#private`
fields – they are equally correct.

## Classes and Objects

- **Class names** are English nouns in PascalCase (`LightElement`,
  `ChargingStation`); **file names** are kebab-case (`light-element.ts`). One
  exported class per file; `main.ts` imports what it uses (relative paths with
  `./` and `.ts`).
- Every property is **declared at the top of the class** with visibility and
  type, and gets its value in the constructor – or at the declaration when the
  start value is fixed (`private wheels: Wheel[] = [];`). The constructor leaves
  the object in a **valid** state – no object that needs a second "init" call to
  work.
- Methods do one thing. Names are verbs (`refuel`, `addWheel`, `getPrice`);
  boolean methods read like questions (`isEmpty`, `hasTicket`, `canDrive`).
- Everything that belongs to an object lives in the object – no global variables
  that classes read or change.
- `this.` for every access to the object's own properties and methods.
- Methods that calculate **return** their result; printing happens in `main.ts`
  or in the output methods the README defines (`print()`, `honk()`).

## Encapsulation

- Properties are `private` by default and `readonly` when they never change;
  only what other classes need is public. Visibility uses the TypeScript
  keywords `private`, `protected` and `public`.
- **Getter methods** (`getFuelLevel(): number`) only where another class or
  `main.ts` needs the value; **setter methods** (`setVolume(volume: number)`)
  only where the README allows the change – and then with validation.
- **Constructor or setter?** Values that never change are set once in the
  constructor and are `readonly`; values that may change get a setter that
  validates; values that only the object changes get neither (the object changes
  them in its own methods – "tell, don't ask").
- The object protects its own consistency: invalid values are rejected
  (`throw new Error(…)`, a `false` result or a clamped value – as the README
  says) and no method can bring the object into an impossible state (negative
  fuel, a grade of 7, more than four wheels).
- Errors from `throw` are caught where the program can react (`try … catch` in
  `main.ts`); `catch` reads the message only after `error instanceof Error`.
- Collections are not handed out for modification: a getter returns a copy
  (`[...this.wheels]`) or a `readonly` array.

## Relationships

- **Has-a:** the related object is a typed property, usually passed in through
  the constructor. Each object gets its own part unless sharing is intended (two
  cars with one shared `Engine` object is a typical bug).
- **Delegation:** a class asks its parts instead of exposing them
  (`car.getPower()` delegates to the engine), and objects talk through methods,
  not by reaching into each other's properties.
- **Has-many:** the array property starts as `[]`; `add…`/`remove…` methods
  check the rules (maximum count, no duplicates); sums, searches and checks loop
  over the collection instead of repeating code per element.

## Inheritance and Polymorphism

- `extends` only for real **is-a** relationships; a part stays a property
  (**has-a**).
- Subclass constructors call `super(…)` first; overriding methods carry the
  `override` keyword and reuse the base version with `super.method()` instead of
  copying its code.
- `protected` only for the members subclasses really need.
- Polymorphic method calls instead of `if`/`else` or `instanceof` chains that
  ask for the type of an object; `abstract` for classes that must not be
  instantiated and methods every subclass has to provide.

## Interfaces and Generics

- Code that only needs a capability is written against the **interface**
  (`devices: Chargeable[]`, a parameter `lockable: Lockable`); classes declare
  `implements`; interface-only imports use `import type`.
- Generic classes and functions instead of duplicated classes or `any`; a
  constraint (`<T extends Item>`) when methods of `T` are called.

## Structure

- `main.ts` is the program: it creates the objects, calls their methods and
  prints the results. Class files contain the class and nothing that runs on
  import.

## Class Diagrams (PlantUML)

- Every class of the code appears with its attributes (`-fuelLevel: number`) and
  methods (`+refuel(litres: number): void`, `+getFuelLevel(): number`);
  visibility `+`, `-`, `#` matches the code.
- Relationships use the right arrow: association `-->` for every has-a
  relationship (the course draws no diamonds – no `o--` and no `*--`; suggest
  `-->` when a student uses them), generalisation `--|>`, realisation `..|>`,
  dependency `..>`; multiplicities (`"1"`, `"*"`) and role names where the
  README asks for them.
- The diagram is inside a ` ```plantuml ` fence with `@startuml` and `@enduml`,
  so the preview renders it.
- **Diagram and code belong together.** When the student draws a diagram, check
  it against the requirements _and_ against the code: every class, every
  attribute with type and visibility, every method with parameters and return
  type, every relationship with the right arrow and multiplicity. Name each
  difference.
