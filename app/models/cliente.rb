class Cliente < ApplicationRecord
  has_many :polizas, dependent: :restrict_with_error

  validates :nombre, presence: true

  scope :buscar, ->(termino) {
    where("unaccent(clientes.nombre) ILIKE unaccent(?)", "%#{sanitize_sql_like(termino.to_s.strip)}%")
  }

  # Nombre normalizado para deduplicación: mayúsculas, sin acentos, espacios colapsados.
  def self.normalizar_nombre(nombre)
    nombre.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").upcase.squeeze(" ").strip
  end

  def polizas_vigentes
    polizas.where(estatus: "vigente")
  end
end
