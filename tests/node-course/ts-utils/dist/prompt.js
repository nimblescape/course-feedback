// prompt() for programs that run in the terminal: shows a question, waits for
// one line from the keyboard and returns it. Use it with
//   import { prompt } from "@majikmate/ts-utils";
import { readSync, writeSync } from "node:fs";
import { isatty } from "node:tty";
/**
 * Shows `message`, reads one line and returns it without the line break.
 * An empty line returns `defaultValue` when there is one.
 * Returns `null` when the input ends (Ctrl+D in the terminal).
 */
export function prompt(message = "Prompt", defaultValue) {
    writeSync(1, defaultValue === undefined
        ? `${message} `
        : `${message} [${defaultValue}] `);
    const line = readLine();
    // Input from a file or a pipe does not appear on the screen: show it, as a terminal would.
    if (line !== null && !isatty(0)) {
        writeSync(1, `${line}\n`);
    }
    if (line === "" && defaultValue !== undefined) {
        return defaultValue;
    }
    return line;
}
/** Reads one line from the input, or returns `null` at the end of the input. */
function readLine() {
    const bytes = [];
    const buffer = new Uint8Array(1);
    while (readSync(0, buffer, 0, 1, null) === 1) {
        if (buffer[0] === 10) {
            return new TextDecoder().decode(new Uint8Array(bytes)).replace(/\r$/, "");
        }
        bytes.push(buffer[0]);
    }
    return bytes.length > 0
        ? new TextDecoder().decode(new Uint8Array(bytes))
        : null;
}
