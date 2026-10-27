document.addEventListener("DOMContentLoaded", () => {
  const toggle = document.querySelector(".menu-toggle");
  const nav = document.querySelector(".main-nav");
  if (toggle && nav) {
    toggle.addEventListener("click", () => {
      const open = nav.classList.toggle("nav-open");
      toggle.setAttribute("aria-expanded", String(open));
      toggle.textContent = open ? "✕" : "☰";
    });
  }
  document.querySelectorAll(".size-option").forEach((button) => {
    button.addEventListener("click", () => {
      document.querySelectorAll(".size-option").forEach((item) => item.classList.remove("selected"));
      button.classList.add("selected");
    });
  });
});
