export default {
  mounted() {
    this.atBottom = true
    this.onScroll = () => {
      this.atBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 80
    }
    this.el.addEventListener("scroll", this.onScroll)
    this.observer = new MutationObserver(() => {
      if (this.atBottom) this.el.scrollTop = this.el.scrollHeight
    })
    this.observer.observe(this.el, {childList: true, subtree: true})
    this.el.scrollTop = this.el.scrollHeight
    this.handleEvent("chat:sent", () => {
      this.atBottom = true
      this.el.scrollTop = this.el.scrollHeight
      document.getElementById("message_message")?.focus()
    })
  },
  destroyed() {
    this.observer.disconnect()
    this.el.removeEventListener("scroll", this.onScroll)
  },
}
