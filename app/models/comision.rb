class Comision < ApplicationRecord
  ESTATUS = %w[por_cobrar pagada].freeze

  belongs_to :recibo
  has_one :poliza, through: :recibo

  enum :estatus, ESTATUS.index_by(&:itself), prefix: true

  validates :recibo_id, uniqueness: true
  validates :porcentaje, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :fecha_cobro, presence: true, if: :estatus_pagada?

  before_validation :calcular_monto, if: -> { monto.blank? && prima_neta.present? && porcentaje.present? }

  scope :por_cobrar, -> { where(estatus: "por_cobrar") }
  scope :pagadas, -> { where(estatus: "pagada") }

  def marcar_pagada!(fecha: Date.current)
    update!(estatus: "pagada", fecha_cobro: fecha)
  end

  private

  def calcular_monto
    self.monto = (prima_neta * porcentaje / 100).round(2)
  end
end
