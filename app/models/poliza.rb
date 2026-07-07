class Poliza < ApplicationRecord
  ASEGURADORAS = %w[inbursa qualitas ana_seguros seguros_atlas otra].freeze
  CANALES = %w[directo broker].freeze
  BROKERS = %w[cano carmona].freeze
  RAMOS = %w[autos moto camion vida gmm danos rc comercio otro].freeze
  FORMAS_PAGO = %w[mensual trimestral semestral anual contado].freeze
  MONEDAS = %w[mxn usd].freeze
  ESTATUS = %w[vigente cancelada no_renovada perdida_total].freeze

  # Meses que avanza el vencimiento al generar el siguiente recibo.
  PERIODOS_MESES = { "mensual" => 1, "trimestral" => 3, "semestral" => 6, "anual" => 12 }.freeze

  belongs_to :cliente
  has_many :recibos, dependent: :destroy
  has_many :comisiones, through: :recibos

  enum :aseguradora, ASEGURADORAS.index_by(&:itself)
  enum :canal, CANALES.index_by(&:itself)
  enum :broker, BROKERS.index_by(&:itself), prefix: true
  enum :ramo, RAMOS.index_by(&:itself)
  enum :forma_pago, FORMAS_PAGO.index_by(&:itself)
  enum :moneda, MONEDAS.index_by(&:itself)
  enum :estatus, ESTATUS.index_by(&:itself), prefix: true

  validates :aseguradora, :canal, :ramo, :forma_pago, :moneda, :estatus, presence: true
  validates :broker, presence: { message: "es obligatorio cuando el canal es broker" }, if: :broker?
  validates :broker, absence: { message: "solo aplica cuando el canal es broker" }, if: :directo?
  validates :prima_total, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :vigentes, -> { estatus_vigente }
  scope :no_vigentes, -> { where.not(estatus: "vigente") }
  scope :necesitan_revision, -> { where(necesita_revision: true) }
  scope :buscar, ->(termino) {
    t = "%#{sanitize_sql_like(termino.to_s.strip)}%"
    left_joins(:cliente).where("unaccent(clientes.nombre) ILIKE unaccent(:t) OR polizas.numero_poliza ILIKE :t", t: t)
  }

  # Fecha del recibo pendiente más próximo; criterio de orden del dashboard.
  def proximo_vencimiento
    recibos.pendientes.minimum(:fecha_vencimiento)
  end

  def periodica?
    PERIODOS_MESES.key?(forma_pago)
  end

  # Posible duplicado: mismo número y aseguradora en otra póliza (warning en UI, no bloquea).
  def posible_duplicado?
    return false if numero_poliza.blank?

    Poliza.where(numero_poliza: numero_poliza, aseguradora: aseguradora).where.not(id: id).exists?
  end

  def limpiar_revision!
    update!(necesita_revision: false, motivo_revision: nil)
  end
end
