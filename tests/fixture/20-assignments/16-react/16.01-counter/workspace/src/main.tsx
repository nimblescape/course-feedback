import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import { App } from "./app.tsx";

const container = document.querySelector("#root");
if (container === null) {
  throw new Error('No element matches the selector "#root".');
}

createRoot(container).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
