require "test_helper"

class ComisionTest < ActiveSupport::TestCase
  test "calcula monto desde prima_neta y porcentaje" do
    comision = Comision.create!(recibo: recibos(:vencido_juan), prima_neta: 4295.07, porcentaje: 8)
    assert_equal 343.61, comision.monto.to_f
  end

  test "no sobreescribe monto capturado a mano" do
    comision = Comision.create!(recibo: recibos(:vencido_juan), prima_neta: 1000, porcentaje: 10, monto: 95)
    assert_equal 95.0, comision.monto.to_f
  end

  test "un recibo solo puede tener una comisión" do
    duplicada = Comision.new(recibo: recibos(:pagado_broker))
    assert_not duplicada.valid?
  end

  test "pagada requiere fecha_cobro" do
    comision = comisiones(:comision_broker)
    comision.estatus = "pagada"
    assert_not comision.valid?
    comision.fecha_cobro = Date.current
    assert comision.valid?
  end

  test "marcar_pagada! asigna estatus y fecha" do
    comision = comisiones(:comision_broker)
    comision.marcar_pagada!
    assert comision.estatus_pagada?
    assert_equal Date.current, comision.fecha_cobro
  end
end
