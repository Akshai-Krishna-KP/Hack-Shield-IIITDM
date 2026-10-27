document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-year]").forEach(el => el.textContent = new Date().getFullYear());
  document.querySelectorAll("[data-current-date]").forEach(el => {
    el.textContent = new Intl.DateTimeFormat(undefined, {weekday:"short", month:"short", day:"numeric"}).format(new Date());
  });
});
