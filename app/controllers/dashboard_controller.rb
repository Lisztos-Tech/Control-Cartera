class DashboardController < ApplicationController
  def index
    recibos = Recibo.pendientes.joins(:poliza).merge(Poliza.vigentes)

    @vencidos = recibos.where(fecha_vencimiento: ...Date.current).count
    @esta_semana = recibos.where(fecha_vencimiento: Date.current..Date.current.end_of_week).count
    @este_mes = recibos.where(fecha_vencimiento: Date.current..Date.current.end_of_month).count
  end
end
