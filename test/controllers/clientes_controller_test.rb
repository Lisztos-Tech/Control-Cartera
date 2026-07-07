require "test_helper"

class ClientesControllerTest < ActionDispatch::IntegrationTest
  test "índice con búsqueda" do
    get clientes_path(q: "maria")
    assert_response :success
    assert_match "MARIA GARCIA", response.body
    assert_no_match "JUAN PEREZ", response.body
  end

  test "búsqueda JSON para el combobox" do
    get clientes_path(q: "juan", format: :json)
    assert_response :success
    nombres = JSON.parse(response.body).map { |c| c["nombre"] }
    assert_includes nombres, "JUAN PEREZ LOPEZ"
  end

  test "detalle muestra pólizas vigentes primero" do
    get cliente_path(clientes(:juan))
    assert_response :success
    cuerpo = response.body
    assert cuerpo.index("1234567") < cuerpo.index("OLD-1"), "la vigente debe listarse antes que la cancelada"
  end

  test "crear y actualizar cliente" do
    assert_difference "Cliente.count", 1 do
      post clientes_path, params: { cliente: { nombre: "NUEVO CLIENTE", telefono: "5512345678" } }
    end
    cliente = Cliente.find_by(nombre: "NUEVO CLIENTE")
    patch cliente_path(cliente), params: { cliente: { email: "nuevo@example.com" } }
    assert_equal "nuevo@example.com", cliente.reload.email
  end

  test "no hay ruta de borrado de clientes" do
    delete "/clientes/#{clientes(:juan).id}"
    assert_response :not_found
    assert Cliente.exists?(clientes(:juan).id)
  end
end
