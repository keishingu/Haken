const choices = document.querySelectorAll("[data-choice]");
const targets = document.querySelectorAll("[data-target]");

choices.forEach((button) => {
  button.addEventListener("click", () => {
    const choice = button.dataset.choice;
    choices.forEach((item) => item.setAttribute("aria-pressed", String(item === button)));
    targets.forEach((target) => {
      const active = target.dataset.target === choice;
      target.hidden = !active;
    });
  });
});
