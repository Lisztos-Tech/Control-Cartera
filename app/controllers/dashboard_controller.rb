class DashboardController < ApplicationController
  def index
    @filtro = FiltroRecibos.new(params)

    base = Recibo.pendientes.joins(poliza: :cliente).includes(poliza: :cliente)
    base = base.merge(Poliza.vigentes)
    @recibos = @filtro.aplicar(base).ordenados_por_vencimiento

    @vencidos = @recibos.where(fecha_vencimiento: ...Date.current).count
    @esta_semana = @recibos.where(fecha_vencimiento: Date.current..Date.current.end_of_week).count
    @este_mes = @recibos.where(fecha_vencimiento: Date.current..Date.current.end_of_month).count
    @necesitan_revision = Poliza.necesitan_revision.count

    respond_to do |format|
      format.html
      format.xlsx do
        render xlsx: "export", filename: "vencimientos_#{Date.current.strftime('%Y%m%d')}.xlsx"
      end
    end
  end
end
