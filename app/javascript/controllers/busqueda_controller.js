import { Controller } from "@hotwired/stimulus"

// Envía el formulario de filtros del dashboard.
// El campo de texto usa debounce; los selects y fechas envían de inmediato.
export default class extends Controller {
  buscar() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.enviar(), 300)
  }

  enviar() {
    this.element.requestSubmit()
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
