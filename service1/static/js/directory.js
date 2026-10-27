document.addEventListener("DOMContentLoaded", () => {
  const input = document.querySelector("#directory-search");
  const cards = [...document.querySelectorAll(".person-card")];
  const empty = document.querySelector("#no-results");
  if (!input) return;
  input.addEventListener("input", () => {
    const query = input.value.trim().toLowerCase();
    let visible = 0;
    cards.forEach(card => {
      const match = (card.dataset.search || "").includes(query);
      card.hidden = !match;
      if (match) visible++;
    });
    if (empty) empty.hidden = visible !== 0;
  });
});
