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
    @poliza = @recibo.poliza
    ok = false

    ActiveRecord::Base.transaction do
      ok = @recibo.update(recibo_params)
      ok &&= @poliza.update(poliza_params) if params[:volver_a] == "vencimientos" && params[:poliza].present?
      raise ActiveRecord::Rollback unless ok
    end

    if ok
      destino = params[:volver_a] == "vencimientos" ? vencimientos_path : @recibo.poliza
      notice = params[:volver_a] == "vencimientos" ? "Vencimiento actualizado." : "Recibo actualizado."
      redirect_to destino, notice: notice
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
      format.html { redirect_back fallback_location: root_path, notice: "Siguiente recibo creado (vence #{helpers.fecha(@nuevo.fecha_vencimiento)})." }
    end
  end

  private

  def set_recibo
    @recibo = Recibo.find(params[:id])
  end

  def recibo_params
    params.require(:recibo).permit(:numero_recibo, :fecha_vencimiento, :importe, :fecha_pago, :estatus)
  end

  def poliza_params
    params.require(:poliza).permit(
      :numero_poliza, :aseguradora, :ramo, :detalle_bien,
      :observaciones, :forma_pago, :moneda
    )
  end
end
