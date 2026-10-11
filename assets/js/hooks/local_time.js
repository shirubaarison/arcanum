export function formatLocalTime(value, locale, timeZone) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null

  return new Intl.DateTimeFormat(locale, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone,
  }).format(date)
}

export default {
  mounted() { this.renderTime() },
  updated() { this.renderTime() },
  renderTime() {
    const formatted = formatLocalTime(this.el.dataset.utc)
    if (formatted) this.el.textContent = formatted
  },
}
