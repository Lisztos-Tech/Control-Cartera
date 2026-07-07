class ComisionesController < ApplicationController
  def index
    @tab = params[:tab] == "pagadas" ? "pagadas" : "por_cobrar"

    base = Comision.includes(recibo: { poliza: :cliente })

    if @tab == "pagadas"
      @comisiones = base.pagadas.order(fecha_cobro: :desc)
    else
      @comisiones = base.por_cobrar.joins(recibo: :poliza).order("polizas.canal, polizas.broker")
      # Por cobrar se agrupa por broker/canal con suma total.
      @grupos = @comisiones.group_by { |c| grupo_de(c.recibo.poliza) }
    end

    respond_to do |format|
      format.html
      format.xlsx do
        render xlsx: "export", filename: "comisiones_#{@tab}_#{Date.current.strftime('%Y%m%d')}.xlsx"
      end
    end
  end

  def edit
    @comision = Comision.find(params[:id])
  end

  def update
    @comision = Comision.find(params[:id])
    if @comision.update(comision_params)
      redirect_to comisiones_path, notice: "Comisión actualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def marcar_pagada
    comision = Comision.find(params[:id])
    fecha = params[:fecha_cobro].presence&.to_date || Date.current
    comision.marcar_pagada!(fecha: fecha)
    redirect_to comisiones_path, notice: "Comisión marcada como pagada (#{helpers.fecha(fecha)})."
  end

  private

  def grupo_de(poliza)
    poliza.broker.present? ? "broker_#{poliza.broker}" : "directo_#{poliza.aseguradora}"
  end

  def comision_params
    params.require(:comision).permit(:prima_neta, :porcentaje, :monto, :estatus, :fecha_cobro, :notas)
  end
end
