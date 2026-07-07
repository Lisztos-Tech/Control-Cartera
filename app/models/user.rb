class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Para mostrar en la UI; cae al correo si no hay nombre capturado.
  def nombre_completo
    [ nombre, apellido ].compact_blank.join(" ").presence || email_address
  end

  def inicial
    (nombre.presence || email_address).first.upcase
  end
end
