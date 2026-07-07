class PolizasController < ApplicationController
  before_action :set_poliza, only: [ :show, :edit, :update, :reactivar ]

  def show
    @recibos = @poliza.recibos.includes(:comision).order(:fecha_vencimiento)
  end

  def new
    @poliza = Poliza.new(cliente_id: params[:cliente_id])
  end

  def create
    @poliza = Poliza.new(poliza_params)
    asignar_cliente

    if @poliza.errors.none? && @poliza.save
      redirect_to @poliza, notice: aviso_creacion
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @poliza.update(poliza_params)
      # Editar y guardar una póliza flaggeada limpia el flag de revisión.
      @poliza.limpiar_revision! if @poliza.necesita_revision?
      redirect_to @poliza, notice: "Póliza actualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Índice de pólizas no vigentes (canceladas / no renovadas / pérdida total).
  def canceladas
    @polizas = Poliza.no_vigentes.includes(:cliente).order(updated_at: :desc)
    @polizas = @polizas.buscar(params[:q]) if params[:q].present?
  end

  # Pólizas flaggeadas por el importador, con su motivo.
  def revision
    @polizas = Poliza.necesitan_revision.includes(:cliente).order(:created_at)
  end

  def reactivar
    @poliza.update!(estatus: "vigente", motivo_cancelacion: nil)
    redirect_to @poliza, notice: "Póliza reactivada."
  end

  private

  def set_poliza
    @poliza = Poliza.find(params[:id])
  end

  def poliza_params
    params.require(:poliza).permit(
      :numero_poliza, :aseguradora, :canal, :broker, :clave_agente, :ramo,
      :cobertura, :forma_pago, :prima_total, :moneda, :detalle_bien,
      :estatus, :motivo_cancelacion, :notas
    )
  end

  # Combobox buscar-o-crear: cliente_id si eligió uno existente,
  # cliente_nombre para crear uno nuevo inline.
  def asignar_cliente
    if params[:poliza][:cliente_id].present?
      @poliza.cliente = Cliente.find_by(id: params[:poliza][:cliente_id])
      @poliza.errors.add(:cliente, "no encontrado") unless @poliza.cliente
    elsif params[:poliza][:cliente_nombre].present?
      @poliza.cliente = Cliente.create!(nombre: params[:poliza][:cliente_nombre].strip.upcase)
      @cliente_creado = true
    else
      @poliza.errors.add(:cliente, "elige un cliente existente o escribe un nombre nuevo")
    end
  end

  def aviso_creacion
    @cliente_creado ? "Póliza creada junto con el cliente #{@poliza.cliente.nombre}." : "Póliza creada."
  end
end
