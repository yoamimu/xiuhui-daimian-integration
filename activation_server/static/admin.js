document.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy-target]");
  if (!button) return;
  const input = document.getElementById(button.dataset.copyTarget);
  if (!input) return;
  await navigator.clipboard.writeText(input.value);
  const original = button.textContent;
  button.textContent = "已复制";
  window.setTimeout(() => { button.textContent = original; }, 1400);
});

document.addEventListener("submit", (event) => {
  const message = event.target.dataset.confirm;
  if (message && !window.confirm(message)) event.preventDefault();
});

const startInput = document.querySelector("[data-license-form] #starts_on");
const expiryInput = document.querySelector("[data-license-form] #expires_on");
if (startInput && expiryInput) {
  startInput.addEventListener("change", () => {
    if (!startInput.value) return;
    const [year, month, day] = startInput.value.split("-").map(Number);
    const nextYear = new Date(Date.UTC(year + 1, month - 1, day));
    if (nextYear.getUTCMonth() !== month - 1) nextYear.setUTCDate(0);
    expiryInput.value = nextYear.toISOString().slice(0, 10);
  });
}
