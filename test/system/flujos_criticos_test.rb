require "application_system_test_case"

# Los 3 flujos críticos del plan: marcar recibo pagado (con siguiente recibo),
# búsqueda/filtros del dashboard, y edición de póliza.
class FlujosCriticosTest < ApplicationSystemTestCase
  setup do
    iniciar_sesion
  end

  test "marcar recibo pagado y crear el siguiente con un clic" do
    recibo = recibos(:vencido_juan) # póliza mensual vigente

    # "Marcar pagado" vive en el detalle de la póliza; la tabla de
    # vencimientos solo tiene el lápiz de edición.
    visit poliza_path(recibo.poliza)
    within "#recibo_#{recibo.id}" do
      click_button "Marcar pagado"
    end

    assert_text "marcado como pagado"
    assert recibo.reload.estatus_pagado?

    assert_difference -> { recibo.poliza.recibos.count }, 1 do
      click_button "Crear siguiente recibo"
      assert_text "Siguiente recibo creado"
    end

    nuevo = recibo.poliza.recibos.order(:created_at).last
    assert_equal recibo.fecha_vencimiento + 1.month, nuevo.fecha_vencimiento
  end

  test "búsqueda y filtros de vencimientos se combinan y viven en la URL" do
    visit vencimientos_path
    assert_text "JUAN PEREZ LOPEZ"
    assert_text "MARIA GARCIA HERNANDEZ"

    fill_in "q", with: "maria"
    assert_no_text "JUAN PEREZ LOPEZ"
    assert_text "MARIA GARCIA HERNANDEZ"
    assert_includes current_url, "q=maria"

    fill_in "q", with: ""
    select "Inbursa", from: "aseguradora"
    assert_text "JUAN PEREZ LOPEZ"
    assert_no_text "Q-5544"
  end

  test "editar una póliza actualiza datos y limpia el flag de revisión" do
    poliza = polizas(:auto_juan)
    poliza.update!(necesita_revision: true, motivo_revision: "importe ilegible")

    visit edit_poliza_path(poliza)
    fill_in "Cobertura", with: "AMPLIA PLUS"
    fill_in "Detalle del bien", with: "FORD RANGER 2014"
    click_button "Guardar cambios"

    assert_current_path poliza_path(poliza)
    assert_text "Póliza actualizada"
    assert_text "AMPLIA PLUS"
    poliza.reload
    assert_equal "FORD RANGER 2014", poliza.detalle_bien
    assert_not poliza.necesita_revision
  end
end
