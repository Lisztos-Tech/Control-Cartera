class VencimientosController < ApplicationController
  def index
    @filtro = FiltroRecibos.new(params)

    base = Recibo.pendientes.joins(poliza: :cliente).includes(poliza: :cliente)
    base = base.merge(Poliza.vigentes)
    @recibos = @filtro.aplicar(base).ordenados_por_vencimiento

    respond_to do |format|
      format.html do
        @pagy, @recibos = pagy(@recibos)
      end
      # El export siempre lleva todas las filas filtradas, no solo la página.
      format.xlsx do
        render xlsx: "export", filename: "vencimientos_#{Date.current.strftime('%Y%m%d')}.xlsx"
      end
    end
  end
end
