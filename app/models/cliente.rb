class Cliente < ApplicationRecord
  has_many :polizas, dependent: :restrict_with_error

  validates :nombre, presence: true

  scope :buscar, ->(termino) {
    where("unaccent(clientes.nombre) ILIKE unaccent(?)", "%#{sanitize_sql_like(termino.to_s.strip)}%")
  }

  # Nombre normalizado para deduplicación: mayúsculas, sin acentos, espacios
  # colapsados (incluye no separables, U+00A0) y sin puntos finales.
  def self.normalizar_nombre(nombre)
    nombre.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "")
          .upcase
          .gsub(/[[:space:]]+/, " ")
          .strip
          .sub(/\.+\z/, "")
  end

  def polizas_vigentes
    polizas.where(estatus: "vigente")
  end
end
