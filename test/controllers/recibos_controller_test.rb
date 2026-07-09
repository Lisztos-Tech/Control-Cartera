require "test_helper"

class RecibosControllerTest < ActionDispatch::IntegrationTest
  test "marcar pagado responde turbo_stream y ofrece siguiente recibo" do
    recibo = recibos(:vencido_juan)
    patch marcar_pagado_recibo_path(recibo), as: :turbo_stream

    assert_response :success
    assert recibo.reload.estatus_pagado?
    assert_match "Crear siguiente recibo", response.body
  end

  test "marcar pagado en póliza de contado no ofrece siguiente" do
    recibo = recibos(:lejano_maria)
    recibo.poliza.update!(forma_pago: "contado")
    patch marcar_pagado_recibo_path(recibo), as: :turbo_stream

    assert_response :success
    assert_no_match "Crear siguiente recibo", response.body
  end

  test "crear siguiente genera recibo con el periodo de la forma de pago" do
    recibo = recibos(:vencido_juan) # mensual
    recibo.marcar_pagado!

    assert_difference "Recibo.count", 1 do
      post crear_siguiente_recibo_path(recibo), as: :turbo_stream
    end

    nuevo = recibo.poliza.recibos.order(:created_at).last
    assert_equal recibo.fecha_vencimiento + 1.month, nuevo.fecha_vencimiento
    assert_equal recibo.importe, nuevo.importe
    assert nuevo.estatus_pendiente?
  end

  test "crear siguiente en contado redirige con alerta" do
    recibo = recibos(:pagado_broker)
    assert_no_difference "Recibo.count" do
      post crear_siguiente_recibo_path(recibo)
    end
    assert_redirected_to root_path
  end

  test "se puede borrar un recibo (error de captura)" do
    recibo = recibos(:proximo_juan)
    poliza = recibo.poliza
    assert_difference "Recibo.count", -1 do
      delete recibo_path(recibo)
    end
    assert_redirected_to poliza_path(poliza)
  end

  test "editar desde vencimientos muestra campos de póliza y recibo" do
    recibo = recibos(:vencido_juan)
    get edit_recibo_path(recibo, volver_a: "vencimientos")

    assert_response :success
    assert_match "Editar vencimiento", response.body
    assert_match "poliza[numero_poliza]", response.body
    assert_match "poliza[observaciones]", response.body
    assert_match "recibo[fecha_vencimiento]", response.body
  end

  test "actualizar desde vencimientos guarda recibo y póliza" do
    recibo = recibos(:vencido_juan)
    poliza = recibo.poliza

    patch recibo_path(recibo, volver_a: "vencimientos"), params: {
      recibo: { importe: 999.99, fecha_vencimiento: recibo.fecha_vencimiento },
      poliza: {
        numero_poliza: poliza.numero_poliza,
        aseguradora: poliza.aseguradora,
        ramo: poliza.ramo,
        forma_pago: poliza.forma_pago,
        moneda: poliza.moneda,
        detalle_bien: "AUTO ACTUALIZADO",
        observaciones: "Nota nueva"
      }
    }

    assert_redirected_to vencimientos_path
    assert_equal 999.99, recibo.reload.importe.to_f
    assert_equal "AUTO ACTUALIZADO", poliza.reload.detalle_bien
    assert_equal "Nota nueva", poliza.observaciones
  end
end
