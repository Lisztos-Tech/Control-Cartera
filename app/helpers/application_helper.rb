module ApplicationHelper
  SEMAFORO_CLASES = {
    rojo: "bg-red-500",
    ambar: "bg-amber-400",
    verde: "bg-green-500"
  }.freeze

  def moneda(importe, moneda = "mxn")
    return "—" if importe.blank?

    simbolo = moneda == "usd" ? "US$" : "$"
    number_to_currency(importe, unit: simbolo, delimiter: ",", separator: ".", format: "%u%n")
  end

  def fecha(valor)
    valor.present? ? l(valor, format: :default) : "—"
  end

  def semaforo_punto(recibo)
    tag.span class: "inline-block h-3 w-3 rounded-full #{SEMAFORO_CLASES[recibo.semaforo]}",
             title: t("app.estatus_recibo.#{recibo.vencido? ? 'vencido' : 'pendiente'}")
  end

  def etiqueta_aseguradora(valor) = t("app.aseguradoras.#{valor}", default: valor.to_s)
  def etiqueta_canal(valor) = t("app.canales.#{valor}", default: valor.to_s)
  def etiqueta_broker(valor) = valor.present? ? t("app.brokers.#{valor}", default: valor.to_s) : "—"
  def etiqueta_ramo(valor) = t("app.ramos.#{valor}", default: valor.to_s)
  def etiqueta_forma_pago(valor) = t("app.formas_pago.#{valor}", default: valor.to_s)
  def etiqueta_estatus_poliza(valor) = t("app.estatus_poliza.#{valor}", default: valor.to_s)
  def etiqueta_estatus_comision(valor) = t("app.estatus_comision.#{valor}", default: valor.to_s)

  def opciones_aseguradora = Poliza::ASEGURADORAS.map { |a| [ etiqueta_aseguradora(a), a ] }
  def opciones_canal = Poliza::CANALES.map { |c| [ etiqueta_canal(c), c ] }
  def opciones_broker = Poliza::BROKERS.map { |b| [ etiqueta_broker(b), b ] }
  def opciones_ramo = Poliza::RAMOS.map { |r| [ etiqueta_ramo(r), r ] }
  def opciones_forma_pago = Poliza::FORMAS_PAGO.map { |f| [ etiqueta_forma_pago(f), f ] }
  def opciones_moneda = Poliza::MONEDAS.map { |m| [ t("app.monedas.#{m}"), m ] }
  def opciones_estatus_poliza = Poliza::ESTATUS.map { |e| [ etiqueta_estatus_poliza(e), e ] }

  def badge_estatus_poliza(poliza)
    clases = poliza.estatus_vigente? ? "bg-green-100 text-green-800" : "bg-gray-200 text-gray-700"
    tag.span etiqueta_estatus_poliza(poliza.estatus), class: "px-2 py-0.5 rounded-full text-xs font-medium #{clases}"
  end
end
