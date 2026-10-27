document.addEventListener("DOMContentLoaded", () => {
  const toggle = document.querySelector("[data-toggle-password]");
  const password = document.querySelector("#pass");
  if (toggle && password) {
    toggle.addEventListener("click", () => {
      const visible = password.type === "password";
      password.type = visible ? "text" : "password";
      toggle.textContent = visible ? "Hide" : "Show";
      toggle.setAttribute("aria-pressed", String(visible));
    });
  }
  const user = document.querySelector("#user");
  if (user && !user.value) user.focus();
});
