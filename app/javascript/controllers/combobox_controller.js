import { Controller } from "@hotwired/stimulus"

// Combobox buscar-o-crear de clientes para el alta de póliza.
// Si se elige un cliente de la lista, viaja poliza[cliente_id];
// si se escribe un nombre libre, viaja poliza[cliente_nombre] y se crea inline.
export default class extends Controller {
  static targets = ["entrada", "clienteId", "lista", "ayuda"]
  static values = { url: String }

  buscar() {
    // Escribir invalida cualquier selección anterior.
    this.clienteIdTarget.value = ""
    this.actualizarAyuda()

    clearTimeout(this.timeout)
    const termino = this.entradaTarget.value.trim()
    if (termino.length < 2) {
      this.cerrar()
      return
    }

    this.timeout = setTimeout(async () => {
      const respuesta = await fetch(`${this.urlValue}?q=${encodeURIComponent(termino)}`, {
        headers: { Accept: "application/json" }
      })
      if (!respuesta.ok) return
      this.mostrar(await respuesta.json())
    }, 250)
  }

  mostrar(clientes) {
    if (clientes.length === 0) {
      this.cerrar()
      return
    }

    this.listaTarget.innerHTML = ""
    clientes.forEach((cliente) => {
      const opcion = document.createElement("button")
      opcion.type = "button"
      opcion.textContent = cliente.nombre
      opcion.className = "block w-full text-left px-3 py-2 text-sm hover:bg-primary-50"
      opcion.addEventListener("mousedown", () => this.elegir(cliente))
      this.listaTarget.appendChild(opcion)
    })
    this.listaTarget.classList.remove("hidden")
  }

  elegir(cliente) {
    this.entradaTarget.value = cliente.nombre
    this.clienteIdTarget.value = cliente.id
    this.cerrar()
    this.actualizarAyuda()
  }

  cerrarLuego() {
    setTimeout(() => this.cerrar(), 150)
  }

  cerrar() {
    this.listaTarget.classList.add("hidden")
  }

  actualizarAyuda() {
    if (this.clienteIdTarget.value) {
      this.ayudaTarget.textContent = "Cliente existente seleccionado."
    } else if (this.entradaTarget.value.trim().length > 0) {
      this.ayudaTarget.textContent = "Se creará un cliente nuevo con este nombre."
    } else {
      this.ayudaTarget.textContent = ""
    }
  }
}
