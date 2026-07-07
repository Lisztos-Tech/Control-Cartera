class RecibosController < ApplicationController
  before_action :set_recibo, except: [ :new, :create ]

  def new
    @poliza = Poliza.find(params[:poliza_id])
    @recibo = @poliza.recibos.new
  end

  def create
    @poliza = Poliza.find(params[:poliza_id])
    @recibo = @poliza.recibos.new(recibo_params)
    if @recibo.save
      redirect_to @poliza, notice: "Recibo creado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @recibo.update(recibo_params)
      redirect_to @recibo.poliza, notice: "Recibo actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Solo recibos se pueden borrar (errores de captura); pólizas y clientes no.
  def destroy
    poliza = @recibo.poliza
    @recibo.destroy
    redirect_to poliza, notice: "Recibo eliminado.", status: :see_other
  end

  def marcar_pagado
    @recibo.marcar_pagado!
    @siguiente = @recibo.siguiente_recibo_propuesto

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path, notice: "Recibo marcado como pagado." }
    end
  end

  def crear_siguiente
    propuesto = @recibo.siguiente_recibo_propuesto
    if propuesto.nil?
      redirect_back fallback_location: root_path, alert: "Esta póliza no genera siguiente recibo."
      return
    end

    @nuevo = propuesto
    @nuevo.save!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path, notice: "Siguiente recibo creado (vence #{l @nuevo.fecha_vencimiento})." }
    end
  end

  private

  def set_recibo
    @recibo = Recibo.find(params[:id])
  end

  def recibo_params
    params.require(:recibo).permit(:numero_recibo, :fecha_vencimiento, :importe, :fecha_pago, :estatus)
  end
end
