# Encapsula los filtros del dashboard de vencimientos (combinables, viven en la URL).
class FiltroRecibos
  ATRIBUTOS = %i[q aseguradora canal broker ramo desde hasta].freeze

  attr_reader(*ATRIBUTOS)

  def initialize(params = {})
    @q = params[:q].presence
    @aseguradora = valida(params[:aseguradora], Poliza::ASEGURADORAS)
    @canal = valida(params[:canal], Poliza::CANALES)
    @broker = valida(params[:broker], Poliza::BROKERS)
    @ramo = valida(params[:ramo], Poliza::RAMOS)
    @desde = parsea_fecha(params[:desde])
    @hasta = parsea_fecha(params[:hasta])
  end

  def aplicar(scope)
    scope = scope.merge(Poliza.buscar(q)) if q
    scope = scope.where(polizas: { aseguradora: aseguradora }) if aseguradora
    scope = scope.where(polizas: { canal: canal }) if canal
    scope = scope.where(polizas: { broker: broker }) if broker
    scope = scope.where(polizas: { ramo: ramo }) if ramo
    scope = scope.where(recibos: { fecha_vencimiento: desde.. }) if desde
    scope = scope.where(recibos: { fecha_vencimiento: ..hasta }) if hasta
    scope
  end

  def activos?
    ATRIBUTOS.any? { |a| public_send(a).present? }
  end

  def to_params
    ATRIBUTOS.index_with { |a| public_send(a) }.compact_blank
  end

  private

  def valida(valor, permitidos)
    permitidos.include?(valor) ? valor : nil
  end

  def parsea_fecha(valor)
    Date.iso8601(valor.to_s)
  rescue Date::Error
    nil
  end
end
