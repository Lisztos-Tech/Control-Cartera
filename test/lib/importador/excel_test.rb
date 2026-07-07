require "test_helper"
require Rails.root.join("lib/importador/excel")
require Rails.root.join("test/support/fixture_excel")

class ImportadorExcelTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  # Fixture .xlsx con los layouts reales y los casos patológicos;
  # se reconstruye en cada corrida para reflejar cambios del builder.
  FIXTURE_PATH = Rails.root.join("tmp/fixture_import_test.xlsx").to_s
  FixtureExcel.construir(FIXTURE_PATH)

  setup do
    Comision.delete_all
    Recibo.delete_all
    Poliza.delete_all
    Cliente.delete_all
    @reporte = Importador::Excel.new(FIXTURE_PATH).importar!
  end

  test "termina sin excepción y crea los registros base" do
    assert Poliza.count.positive?
    assert Recibo.count.positive?
    assert Cliente.count.positive?
  end

  test "el reporte cuadra con lo creado" do
    assert_equal Cliente.count, @reporte[:clientes_creados]
    assert_equal Poliza.count, @reporte[:polizas_creadas]
    assert_equal Recibo.count, @reporte[:recibos_creados]
    assert_equal Comision.count, @reporte[:comisiones_creadas]
  end

  test "consolida filas duplicadas de renovación en una póliza con varios recibos" do
    polizas = Poliza.where(numero_poliza: "111111")
    assert_equal 1, polizas.count
    assert_equal 2, polizas.first.recibos.count
    assert_equal [ Date.new(2026, 8, 15), Date.new(2026, 9, 15) ],
                 polizas.first.recibos.order(:fecha_vencimiento).pluck(:fecha_vencimiento)
  end

  test "normaliza fecha serial de Excel y formas de pago abreviadas" do
    poliza = Poliza.find_by(numero_poliza: "222222")
    assert_equal Date.new(2026, 2, 24), poliza.recibos.first.fecha_vencimiento
    assert_equal "anual", poliza.forma_pago # "4.AN"
    assert_equal "semestral", Poliza.find_by(numero_poliza: "333333").forma_pago # "3.SEM"
  end

  test "separa nombre contaminado y manda la cola a notas" do
    poliza = Poliza.find_by(numero_poliza: "222222")
    assert_equal "MARIA GARCIA HERNANDEZ", poliza.cliente.nombre
    assert_match(/esta poiza la pagué yo/, poliza.notas)
  end

  test "importe basura queda en null, va a notas y flaggea" do
    poliza = Poliza.find_by(numero_poliza: "333333")
    assert_nil poliza.recibos.first.importe
    assert_match(/PAGADA/, poliza.notas)
    assert poliza.necesita_revision
    assert_match(/importe ilegible/, poliza.motivo_revision)
  end

  test "parsea importes con formatos mixtos" do
    assert_equal 4295.07, Poliza.find_by(numero_poliza: "Q-1002").recibos.first.importe.to_f
    assert_equal 3856.12, Poliza.find_by(numero_poliza: "AT-88").recibos.first.importe.to_f
    assert_equal 4921.5, Poliza.find_by(numero_poliza: "111111").recibos.first.importe.to_f
  end

  test "hoja qualitas usa el layout posicional real" do
    poliza = Poliza.find_by(numero_poliza: "Q-1002")
    assert_equal "qualitas", poliza.aseguradora
    assert_equal "directo", poliza.canal
    assert_equal "camion", poliza.ramo
    assert_equal "trimestral", poliza.forma_pago
    assert_equal "FREIGHTLINER", poliza.detalle_bien
    # La columna extra sin nombre va a observaciones, separada del bien
    assert_equal "ANGELICA contacto@mail.com", poliza.observaciones
  end

  test "hoja broker toma aseguradora de CIA y broker de AGENTE" do
    ana = Poliza.find_by(numero_poliza: "AN-77")
    assert_equal "ana_seguros", ana.aseguradora
    assert_equal "broker", ana.canal
    assert_equal "cano", ana.broker

    atlas = Poliza.find_by(numero_poliza: "AT-88")
    assert_equal "seguros_atlas", atlas.aseguradora
    assert_equal "carmona", atlas.broker
  end

  test "CIA y broker no reconocidos se flaggean" do
    poliza = Poliza.find_by(numero_poliza: "GN-99")
    assert poliza.necesita_revision
    assert_match(/CIA/, poliza.motivo_revision)
    assert_match(/broker/, poliza.motivo_revision)
    assert_nil poliza.broker
  end

  test "fila broker sin número crea póliza sin número con la nota separada" do
    poliza = Poliza.joins(:cliente).find_by(clientes: { nombre: "ISIDRO RABADAN" })
    assert poliza.present?
    assert_nil poliza.numero_poliza
    assert_equal "broker", poliza.canal
    assert_match(/cotizar en enero/, poliza.notas)
  end

  test "polizas vida: strings parseados, moneda, recibo pagado y comisión del reporte" do
    usd = Poliza.find_by(numero_poliza: "VI-501")
    assert_equal "vida", usd.ramo
    assert_equal "usd", usd.moneda
    assert_equal "mensual", usd.forma_pago # efecto→vencimiento = 31 días

    recibo = usd.recibos.first
    assert_equal Date.new(2026, 9, 28), recibo.fecha_vencimiento
    assert_equal 137.8, recibo.importe.to_f
    assert_equal "94255407", recibo.numero_recibo
    assert recibo.estatus_pagado?
    assert_equal Date.new(2026, 8, 28), recibo.fecha_pago
    assert_equal 115.76, recibo.comision.monto.to_f
    assert recibo.comision.estatus_pagada?

    mxn = Poliza.find_by(numero_poliza: "VI-502")
    assert_equal "mxn", mxn.moneda
    assert_equal "anual", mxn.forma_pago
    assert_equal 12_000.0, mxn.recibos.first.importe.to_f
    assert mxn.recibos.first.estatus_pendiente?
    assert_nil mxn.recibos.first.comision # comisión "0" no se crea
  end

  test "canceladas: estatus derivado del texto libre y motivo capturado" do
    assert_equal "no_renovada", Poliza.find_by(numero_poliza: "C-100").estatus
    assert_equal "perdida_total", Poliza.find_by(numero_poliza: "C-200").estatus
    assert_equal "cancelada", Poliza.find_by(numero_poliza: "C-300").estatus
    assert_match(/no se renovó/, Poliza.find_by(numero_poliza: "C-100").motivo_cancelacion)
    # La mención de QUALITAS en el texto libre define la aseguradora
    assert_equal "qualitas", Poliza.find_by(numero_poliza: "C-300").aseguradora
    # Canceladas no generan recibos pendientes
    assert_equal 0, Poliza.find_by(numero_poliza: "C-100").recibos.count
  end

  test "comisiones: bloque viejo (POLIZA/ASEGURADO/PRIMA) vincula por número" do
    comision = Poliza.find_by(numero_poliza: "Q-1001").comisiones.first
    assert comision.present?
    assert_equal 4295.07, comision.prima_neta.to_f
  end

  test "comisiones: bloque nuevo con porcentaje fraccionario y typo de fecha" do
    poliza = Poliza.find_by(numero_poliza: "AN-77")
    comision = poliza.comisiones.first
    assert_equal 3856.12, comision.prima_neta.to_f
    assert_equal 10.0, comision.porcentaje.to_f
    assert_equal 385.61, comision.monto.to_f # calculado de prima × %
    assert poliza.necesita_revision
    assert_match(/ambigua/, poliza.motivo_revision)
  end

  test "comisiones: porcentaje corrupto se ignora pero el monto explícito se guarda" do
    comision = Poliza.find_by(numero_poliza: "AT-88").comisiones.first
    assert_nil comision.porcentaje
    assert_equal 274.16, comision.monto.to_f
  end

  test "comisiones sin póliza vinculable se ignoran con motivo" do
    assert @reporte.ignoradas.any? { |i| i[:motivo].include?("ZZ-404") }
  end

  test "fila sin contratante se ignora con motivo" do
    assert_nil Poliza.find_by(numero_poliza: "555555")
    assert @reporte.ignoradas.any? { |i| i[:motivo].include?("sin nombre de contratante") }
  end

  test "sección VRIM crea cliente ficticio con nombres en notas, sin pólizas" do
    vrim = Cliente.find_by(nombre: "PENDIENTES VRIM")
    assert vrim.present?
    assert_match(/LUIS LARA/, vrim.notas)
    assert_match(/ROSA MELANO/, vrim.notas)
    assert_equal 0, vrim.polizas.count
  end

  test "par dudoso WEBSTER/BREWSTER no se fusiona y se reporta" do
    assert Cliente.buscar("ANDERSON WEBSTER").exists?
    assert Cliente.buscar("ANDERSON BREWSTER").exists?
    assert @reporte.pares_dudosos.any? { |p|
      [ p[:nombre_a], p[:nombre_b] ].sort == [ "ANDERSON BREWSTER", "ANDERSON WEBSTER" ]
    }
  end

  test "reconciliación reporta pólizas de Hoja1 ausentes en primarias" do
    assert @reporte.reconciliacion.any? { |r| r[:numero_poliza] == "99990001" }
    assert_not @reporte.reconciliacion.any? { |r| r[:numero_poliza] == "111111" }
  end

  test "es idempotente tras limpiar la base (destroy + reimport)" do
    conteos = [ Cliente.count, Poliza.count, Recibo.count, Comision.count ]

    Comision.delete_all
    Recibo.delete_all
    Poliza.delete_all
    Cliente.delete_all
    Importador::Excel.new(FIXTURE_PATH).importar!

    assert_equal conteos, [ Cliente.count, Poliza.count, Recibo.count, Comision.count ]
  end

  test "el reporte se imprime sin errores" do
    io = StringIO.new
    @reporte.imprimir(io)
    assert_match(/RESUMEN DEL IMPORT/, io.string)
    assert_match(/Necesitan revisión/, io.string)
  end
end
