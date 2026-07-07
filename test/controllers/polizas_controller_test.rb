require "test_helper"

class PolizasControllerTest < ActionDispatch::IntegrationTest
  test "detalle muestra datos, recibos y comisiones" do
    get poliza_path(polizas(:broker_maria))
    assert_response :success
    assert_match "Q-5544", response.body
    assert_match "MARIA GARCIA HERNANDEZ", response.body
    assert_match "Por cobrar", response.body
  end

  test "crear póliza con cliente existente" do
    assert_difference "Poliza.count", 1 do
      assert_no_difference "Cliente.count" do
        post polizas_path, params: { poliza: {
          cliente_id: clientes(:juan).id,
          numero_poliza: "NUEVA-1", aseguradora: "qualitas", canal: "directo",
          ramo: "autos", forma_pago: "anual", moneda: "mxn", estatus: "vigente"
        } }
      end
    end
    assert_equal clientes(:juan), Poliza.find_by(numero_poliza: "NUEVA-1").cliente
  end

  test "crear póliza con cliente nuevo inline" do
    assert_difference [ "Poliza.count", "Cliente.count" ], 1 do
      post polizas_path, params: { poliza: {
        cliente_nombre: "cliente nuevo inline",
        numero_poliza: "NUEVA-2", aseguradora: "inbursa", canal: "directo",
        ramo: "vida", forma_pago: "anual", moneda: "usd", estatus: "vigente"
      } }
    end
    assert_equal "CLIENTE NUEVO INLINE", Poliza.find_by(numero_poliza: "NUEVA-2").cliente.nombre
  end

  test "crear póliza sin cliente falla con mensaje" do
    assert_no_difference "Poliza.count" do
      post polizas_path, params: { poliza: {
        numero_poliza: "NUEVA-3", aseguradora: "inbursa", canal: "directo",
        ramo: "autos", forma_pago: "anual", moneda: "mxn", estatus: "vigente"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "editar una póliza flaggeada limpia el flag" do
    poliza = polizas(:auto_juan)
    poliza.update!(necesita_revision: true, motivo_revision: "importe ilegible")

    patch poliza_path(poliza), params: { poliza: { cobertura: "AMPLIA PLUS" } }

    assert_redirected_to poliza_path(poliza)
    poliza.reload
    assert_not poliza.necesita_revision
    assert_nil poliza.motivo_revision
  end

  test "canceladas lista solo no vigentes con búsqueda" do
    get canceladas_polizas_path
    assert_response :success
    assert_match "OLD-1", response.body
    assert_no_match "Q-5544", response.body

    get canceladas_polizas_path(q: "no existe nadie asi")
    assert_no_match "OLD-1", response.body
  end

  test "reactivar cambia estatus a vigente" do
    poliza = polizas(:cancelada_juan)
    patch reactivar_poliza_path(poliza)
    assert poliza.reload.estatus_vigente?
    assert_nil poliza.motivo_cancelacion
  end

  test "vista de revisión lista flaggeadas con motivo" do
    polizas(:auto_juan).update!(necesita_revision: true, motivo_revision: "fecha ambigua (7/02)")
    get revision_polizas_path
    assert_response :success
    assert_match "fecha ambigua", response.body
  end

  test "no hay ruta de borrado de pólizas" do
    delete "/polizas/#{polizas(:auto_juan).id}"
    assert_response :not_found
    assert Poliza.exists?(polizas(:auto_juan).id)
  end
end
