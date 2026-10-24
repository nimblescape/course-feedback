// Runs Deno-style student programs with Node: prompt(), the Deno functions the
// courses teach and jsr: imports. Loaded with `node --import`.
import fs from "node:fs";
import { registerHooks } from "node:module";
import "./seed-random.mjs";

// jsr:@scope/name[@version][/path] → the npm package @jsr/scope__name[/path]
// that the check installed next to this file.
const tools = new URL("./", import.meta.url).href;
registerHooks({
  resolve(specifier, context, nextResolve) {
    const match = /^jsr:@([^/]+)\/([^/@]+)(?:@[^/]*)?(\/.*)?$/.exec(specifier);
    if (!match) return nextResolve(specifier, context);
    const [, scope, name, path = ""] = match;
    return nextResolve(`@jsr/${scope}__${name}${path}`, { ...context, parentURL: tools });
  },
});

// The input is piped, not typed: echo each answer like a terminal does.
const echo = !process.stdin.isTTY;

function readLine() {
  const bytes = [];
  const buffer = Buffer.alloc(1);
  while (fs.readSync(0, buffer, 0, 1, null) === 1) {
    if (buffer[0] === 10) return Buffer.from(bytes).toString("utf8").replace(/\r$/, "");
    bytes.push(buffer[0]);
  }
  return bytes.length > 0 ? Buffer.from(bytes).toString("utf8") : null;
}

// Like Deno: "message [default] ", one line, the default on an empty line.
// When the prepared answers are used up, the program is stopped.
globalThis.prompt = (message = "Prompt", defaultValue) => {
  defaultValue ??= null;
  process.stdout.write(defaultValue === null ? `${message} ` : `${message} [${defaultValue}] `);
  const line = readLine();
  if (line === null) {
    process.stdout.write("\n[end of the prepared input: the program was stopped]\n");
    process.exit(0);
  }
  if (echo) process.stdout.write(`${line}\n`);
  return line === "" && defaultValue !== null ? defaultValue : line;
};

globalThis.Deno = {
  readTextFileSync: (path) => fs.readFileSync(path, "utf8"),
  writeTextFileSync: (path, data) => fs.writeFileSync(path, data),
  version: { deno: "2", v8: process.versions.v8, typescript: "5" },
};
