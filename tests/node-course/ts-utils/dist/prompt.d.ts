/**
 * Shows `message`, reads one line and returns it without the line break.
 * An empty line returns `defaultValue` when there is one.
 * Returns `null` when the input ends (Ctrl+D in the terminal).
 */
export declare function prompt(message?: string, defaultValue?: string): string | null;
