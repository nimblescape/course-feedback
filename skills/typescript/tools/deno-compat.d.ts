// Types of the Deno functions that deno-compat.mjs provides. prompt() comes
// from the DOM library.
declare namespace Deno {
  function readTextFileSync(path: string | URL): string;
  function writeTextFileSync(path: string | URL, data: string): void;
  const version: { deno: string; v8: string; typescript: string };
}
