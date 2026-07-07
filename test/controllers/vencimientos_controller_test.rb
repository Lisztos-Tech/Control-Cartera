require "test_helper"

class VencimientosControllerTest < ActionDispatch::IntegrationTest
  test "muestra recibos pendientes ordenados por vencimiento" do
    get vencimientos_path
    assert_response :success
    assert_match "JUAN PEREZ LOPEZ", response.body
    # El pagado no aparece
    assert_no_match "recibo_#{recibos(:pagado_broker).id}\"", response.body
  end

  test "filtra por aseguradora" do
    get vencimientos_path(aseguradora: "qualitas")
    assert_response :success
    assert_no_match "JUAN PEREZ LOPEZ", response.body
  end

  test "busca por nombre de cliente" do
    get vencimientos_path(q: "maria garcia")
    assert_response :success
    assert_match "MARIA GARCIA", response.body
    assert_no_match "JUAN PEREZ", response.body
  end

  test "filtra por rango de fechas" do
    get vencimientos_path(desde: Date.current.to_s)
    assert_response :success
    assert_no_match "recibo_#{recibos(:vencido_juan).id}", response.body
  end

  test "parámetros de filtro inválidos se ignoran sin error" do
    get vencimientos_path(aseguradora: "'; DROP TABLE--", desde: "no-es-fecha")
    assert_response :success
  end

  test "exporta xlsx respetando filtros y el archivo abre sin errores" do
    get vencimientos_path(format: :xlsx, aseguradora: "inbursa")
    assert_response :success
    assert_equal Mime[:xlsx].to_s, response.media_type

    archivo = Rails.root.join("tmp/export_test.xlsx")
    File.binwrite(archivo, response.body)
    libro = Roo::Excelx.new(archivo.to_s)
    assert_equal "Vencimientos", libro.sheets.first
    assert_equal "Cliente", libro.cell(1, 2)
    # Filtrado: solo pólizas Inbursa
    contenido = (2..libro.last_row).map { |fila| libro.cell(fila, 4) }
    assert contenido.all? { |aseg| aseg == "Inbursa" }
  end
end
