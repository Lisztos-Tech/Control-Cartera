class Recibo < ApplicationRecord
  ESTATUS = %w[pendiente pagado].freeze

  belongs_to :poliza
  has_one :comision, dependent: :destroy

  enum :estatus, ESTATUS.index_by(&:itself), prefix: true

  validates :fecha_vencimiento, presence: true
  validates :importe, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :fecha_pago, presence: true, if: :estatus_pagado?

  # "vencido" no se persiste: es un pendiente con fecha pasada.
  scope :pendientes, -> { where(estatus: "pendiente") }
  scope :pagados, -> { where(estatus: "pagado") }
  scope :vencidos, -> { pendientes.where(fecha_vencimiento: ...Date.current) }
  scope :por_vencer, ->(dias) { pendientes.where(fecha_vencimiento: Date.current..(Date.current + dias)) }
  scope :ordenados_por_vencimiento, -> { order(:fecha_vencimiento) }

  def vencido?
    estatus_pendiente? && fecha_vencimiento < Date.current
  end

  # Semáforo del dashboard: :rojo vencido, :ambar <= 30 días, :verde el resto.
  def semaforo
    return :rojo if vencido?
    return :ambar if fecha_vencimiento <= Date.current + 30

    :verde
  end

  # Marca pagado y devuelve el borrador del siguiente recibo (sin guardar)
  # para que la UI pida confirmación con un clic.
  def marcar_pagado!(fecha: Date.current)
    update!(estatus: "pagado", fecha_pago: fecha)
  end

  def siguiente_recibo_propuesto
    return nil unless poliza.estatus_vigente? && poliza.periodica?

    meses = Poliza::PERIODOS_MESES.fetch(poliza.forma_pago)
    poliza.recibos.new(
      fecha_vencimiento: fecha_vencimiento + meses.months,
      importe: importe,
      numero_recibo: siguiente_numero_recibo
    )
  end

  private

  # "2/12" -> "3/12"; si no tiene ese formato, no proponer número.
  def siguiente_numero_recibo
    return nil unless numero_recibo.to_s.match?(%r{\A\d+/\d+\z})

    actual, total = numero_recibo.split("/").map(&:to_i)
    return nil if actual >= total

    "#{actual + 1}/#{total}"
  end
end
