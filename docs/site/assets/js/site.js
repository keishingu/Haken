const choices = document.querySelectorAll("[data-choice]");
const destinations = document.querySelectorAll("[data-destination]");
const labels = { write: "書く", research: "調べる", talk: "話す" };
const status = document.querySelector("#demo-status");

choices.forEach((button) => {
  button.addEventListener("click", () => {
    const choice = button.dataset.choice;
    choices.forEach((item) => {
      const active = item === button;
      item.classList.toggle("is-active", active);
      item.setAttribute("aria-pressed", String(active));
    });
    destinations.forEach((item) => item.classList.toggle("is-active", item.dataset.destination === choice));
    document.querySelector("#route-map")?.setAttribute("data-active", choice);
    if (status) status.textContent = `「${labels[choice]}」へ移りました`;
  });
});
