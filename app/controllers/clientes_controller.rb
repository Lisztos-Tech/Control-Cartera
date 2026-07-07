class ClientesController < ApplicationController
  before_action :set_cliente, only: [ :show, :edit, :update ]

  def index
    @clientes = Cliente.order(:nombre)
    @clientes = @clientes.buscar(params[:q]) if params[:q].present?

    respond_to do |format|
      format.html do
        @pagy, @clientes = pagy(@clientes)
      end
      # El combobox de "Nueva póliza" consume esta búsqueda.
      format.json { render json: @clientes.limit(10).select(:id, :nombre) }
    end
  end

  def show
    @polizas = @cliente.polizas.order(
      Arel.sql("CASE WHEN estatus = 'vigente' THEN 0 ELSE 1 END"), created_at: :desc
    )
  end

  def new
    @cliente = Cliente.new
  end

  def create
    @cliente = Cliente.new(cliente_params)
    if @cliente.save
      redirect_to @cliente, notice: "Cliente creado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @cliente.update(cliente_params)
      redirect_to @cliente, notice: "Cliente actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_cliente
    @cliente = Cliente.find(params[:id])
  end

  def cliente_params
    params.require(:cliente).permit(:nombre, :telefono, :email, :notas)
  end
end
