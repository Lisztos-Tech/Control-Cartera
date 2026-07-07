require "test_helper"

class ReciboTest < ActiveSupport::TestCase
  test "vencidos son pendientes con fecha pasada" do
    assert_includes Recibo.vencidos, recibos(:vencido_juan)
    assert_not_includes Recibo.vencidos, recibos(:proximo_juan)
    assert_not_includes Recibo.vencidos, recibos(:pagado_broker)
  end

  test "semaforo rojo para vencido, ambar <= 30 días, verde después" do
    assert_equal :rojo, recibos(:vencido_juan).semaforo
    assert_equal :ambar, recibos(:proximo_juan).semaforo
    assert_equal :verde, recibos(:lejano_maria).semaforo
  end

  test "recibo pagado requiere fecha_pago" do
    recibo = recibos(:vencido_juan)
    recibo.estatus = "pagado"
    assert_not recibo.valid?
    recibo.fecha_pago = Date.current
    assert recibo.valid?
  end

  test "marcar_pagado! asigna estatus y fecha" do
    recibo = recibos(:vencido_juan)
    recibo.marcar_pagado!
    assert recibo.estatus_pagado?
    assert_equal Date.current, recibo.fecha_pago
  end

  test "siguiente_recibo_propuesto avanza según forma de pago" do
    recibo = recibos(:vencido_juan) # póliza mensual
    propuesto = recibo.siguiente_recibo_propuesto
    assert_equal recibo.fecha_vencimiento + 1.month, propuesto.fecha_vencimiento
    assert_equal recibo.importe, propuesto.importe
    assert_equal "3/12", propuesto.numero_recibo
    assert propuesto.new_record?
  end

  test "siguiente_recibo_propuesto es nil para contado" do
    assert_nil recibos(:pagado_broker).siguiente_recibo_propuesto
  end

  test "siguiente_recibo_propuesto es nil para póliza no vigente" do
    poliza = polizas(:auto_juan)
    poliza.update!(estatus: "cancelada")
    assert_nil recibos(:vencido_juan).reload.siguiente_recibo_propuesto
  end

  test "no propone número si el actual es el último" do
    recibo = recibos(:lejano_maria) # "1/1", póliza anual vigente
    propuesto = recibo.siguiente_recibo_propuesto
    assert_nil propuesto.numero_recibo
    assert_equal recibo.fecha_vencimiento + 12.months, propuesto.fecha_vencimiento
  end
end
