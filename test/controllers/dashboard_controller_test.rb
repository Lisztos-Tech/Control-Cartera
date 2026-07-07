require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "root muestra recibos pendientes ordenados por vencimiento" do
    get root_path
    assert_response :success
    assert_match "JUAN PEREZ LOPEZ", response.body
    assert_match "Vencidos", response.body
    # El pagado no aparece
    assert_no_match "recibo_#{recibos(:pagado_broker).id}\"", response.body
  end

  test "filtra por aseguradora" do
    get root_path(aseguradora: "qualitas")
    assert_response :success
    assert_no_match "JUAN PEREZ LOPEZ", response.body
  end

  test "busca por nombre de cliente" do
    get root_path(q: "maria garcia")
    assert_response :success
    assert_match "MARIA GARCIA", response.body
    assert_no_match "JUAN PEREZ", response.body
  end

  test "filtra por rango de fechas" do
    get root_path(desde: Date.current.to_s)
    assert_response :success
    assert_no_match "recibo_#{recibos(:vencido_juan).id}", response.body
  end

  test "parámetros de filtro inválidos se ignoran sin error" do
    get root_path(aseguradora: "'; DROP TABLE--", desde: "no-es-fecha")
    assert_response :success
  end

  test "exporta xlsx respetando filtros" do
    get root_path(format: :xlsx, aseguradora: "inbursa")
    assert_response :success
    assert_equal Mime[:xlsx].to_s, response.media_type
  end
end
