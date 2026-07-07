require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "sin sesión redirige al login" do
    cerrar_sesion
    get root_path
    assert_redirected_to new_session_path
  end

  test "login con credenciales correctas entra al dashboard" do
    cerrar_sesion
    post session_url, params: { email_address: users(:irma).email_address, password: "password" }
    assert_redirected_to root_url
    get root_path
    assert_response :success
  end

  test "login con credenciales incorrectas rebota" do
    cerrar_sesion
    post session_url, params: { email_address: users(:irma).email_address, password: "mala" }
    assert_redirected_to new_session_path
  end

  test "logout cierra la sesión" do
    cerrar_sesion
    get root_path
    assert_redirected_to new_session_path
  end

  test "no existen rutas de registro ni de reset de contraseña" do
    cerrar_sesion
    get "/passwords/new"
    assert_response :not_found
  end
end
