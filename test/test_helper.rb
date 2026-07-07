ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Suite pequeña de una sola app; correr en un proceso evita el overhead
    # (y cuelgues) de crear bases de datos paralelas.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  # Cuenta única: casi todas las pantallas requieren sesión.
  setup { iniciar_sesion }

  def iniciar_sesion(user = users(:irma))
    post session_url, params: { email_address: user.email_address, password: "password" }
  end

  def cerrar_sesion
    delete session_url
  end
end
