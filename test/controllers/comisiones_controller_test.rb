require "test_helper"

class ComisionesControllerTest < ActionDispatch::IntegrationTest
  test "por cobrar agrupa por broker con suma total" do
    get comisiones_path
    assert_response :success
    assert_match "Broker Cano", response.body
    assert_match "MARIA GARCIA HERNANDEZ", response.body
    assert_match "Total:", response.body
  end

  test "tab pagadas lista solo pagadas" do
    comisiones(:comision_broker).marcar_pagada!(fecha: Date.current - 5)
    get comisiones_path(tab: "pagadas")
    assert_response :success
    assert_match "MARIA GARCIA HERNANDEZ", response.body

    get comisiones_path(tab: "por_cobrar")
    assert_no_match "MARIA GARCIA HERNANDEZ", response.body
  end

  test "marcar pagada con fecha" do
    comision = comisiones(:comision_broker)
    patch marcar_pagada_comision_path(comision), params: { fecha_cobro: "2026-06-01" }
    assert_redirected_to comisiones_path
    comision.reload
    assert comision.estatus_pagada?
    assert_equal Date.new(2026, 6, 1), comision.fecha_cobro
  end

  test "exporta xlsx" do
    get comisiones_path(format: :xlsx)
    assert_response :success
    assert_equal Mime[:xlsx].to_s, response.media_type
  end
end
