require "test_helper"
require Rails.root.join("lib/importador/limpieza")

class LimpiezaTest < ActiveSupport::TestCase
  L = Importador::Limpieza

  # --- Fechas (regla 1) ---

  test "fecha datetime nativa" do
    res = L.parsear_fecha(DateTime.new(2026, 5, 30, 10, 0))
    assert_equal Date.new(2026, 5, 30), res.fecha
    assert_not res.ambigua
  end

  test "fecha serial de Excel (46077 = 2026-02-24)" do
    res = L.parsear_fecha(46077)
    assert_equal Date.new(2026, 2, 24), res.fecha
  end

  test "serial fuera de rango plausible no es fecha" do
    assert_nil L.parsear_fecha(123)
  end

  test "fecha string dd/mm/yyyy sin ambigüedad" do
    res = L.parsear_fecha("13/09/2023")
    assert_equal Date.new(2023, 9, 13), res.fecha
    assert_not res.ambigua
  end

  test "fecha string US m/d/yyyy detectada por día > 12" do
    res = L.parsear_fecha("12/15/2023")
    assert_equal Date.new(2023, 12, 15), res.fecha
    assert_not res.ambigua
  end

  test "typo con doble slash se tolera y 7/02 queda ambigua como dd/mm" do
    res = L.parsear_fecha("7/02//2024")
    assert_equal Date.new(2024, 2, 7), res.fecha
    assert res.ambigua
  end

  test "misma cifra en día y mes no es ambigua" do
    res = L.parsear_fecha("5/5/2024")
    assert_not res.ambigua
  end

  test "texto que no es fecha devuelve nil" do
    assert_nil L.parsear_fecha("PENDIENTE")
    assert_nil L.parsear_fecha("")
    assert_nil L.parsear_fecha(nil)
  end

  test "fecha inválida (32/01) devuelve nil" do
    assert_nil L.parsear_fecha("32/01/2024")
  end

  # --- Importes (regla 2) ---

  test "importe numérico directo" do
    assert_equal 4921.5, L.parsear_importe(4921.5).importe.to_f
  end

  test "importe con signo de pesos y comas de miles" do
    assert_equal 4921.5, L.parsear_importe("$4,921.50").importe.to_f
  end

  test "importe con coma decimal europea" do
    assert_equal 4295.07, L.parsear_importe("4295,07").importe.to_f
  end

  test "importe con punto de miles y coma decimal" do
    assert_equal 3856.12, L.parsear_importe("$ 3.856,12").importe.to_f
  end

  test "basura en columna de importe se conserva como texto" do
    res = L.parsear_importe("PAGADA")
    assert_nil res.importe
    assert_equal "PAGADA", res.texto
  end

  test "importe vacío devuelve nil" do
    assert_nil L.parsear_importe("")
    assert_nil L.parsear_importe(nil)
  end

  # --- Nombres (regla 3) ---

  test "nombre limpio queda intacto" do
    res = L.separar_nombre("JUAN PEREZ LOPEZ")
    assert_equal "JUAN PEREZ LOPEZ", res.nombre
    assert_nil res.notas
  end

  test "cola en minúsculas se separa a notas" do
    res = L.separar_nombre("MARIA GARCIA esta poiza la pagué yo")
    assert_equal "MARIA GARCIA", res.nombre
    assert_equal "esta poiza la pagué yo", res.notas
  end

  test "colapsa espacios múltiples y padding" do
    res = L.separar_nombre("   PEDRO    SANCHEZ                    Pedir renovacion")
    assert_equal "PEDRO SANCHEZ", res.nombre
    assert_equal "Pedir renovacion", res.notas
  end

  test "tokens numéricos como 2/2 cortan el nombre" do
    res = L.separar_nombre("LUISA LARA 2/2")
    assert_equal "LUISA LARA", res.nombre
    assert_equal "2/2", res.notas
  end

  test "nombres con acentos en mayúsculas se conservan" do
    res = L.separar_nombre("JOSÉ MARTÍNEZ")
    assert_equal "JOSÉ MARTÍNEZ", res.nombre
  end

  # --- Mapeos ---

  test "mapear ramo" do
    assert_equal "autos", L.mapear_ramo("AUTOS")
    assert_equal "moto", L.mapear_ramo("MOTO")
    assert_equal "vida", L.mapear_ramo("VIDA INDIVIDUAL")
    assert_equal "otro", L.mapear_ramo("XYZ")
    assert_nil L.mapear_ramo("")
  end

  test "mapear forma de pago" do
    assert_equal "mensual", L.mapear_forma_pago("MENSUAL")
    assert_equal "semestral", L.mapear_forma_pago("3.SEM")
    assert_equal "contado", L.mapear_forma_pago("CONTADO")
    assert_nil L.mapear_forma_pago("???")
  end

  test "mapear moneda NACIONAL/DOLARES" do
    assert_equal "usd", L.mapear_moneda("DOLARES")
    assert_equal "mxn", L.mapear_moneda("NACIONAL")
    assert_equal "mxn", L.mapear_moneda(nil)
  end

  test "estatus de cancelación según texto" do
    assert_equal "no_renovada", L.mapear_estatus_cancelacion("no se renovó")
    assert_equal "perdida_total", L.mapear_estatus_cancelacion("PT POR ROBO")
    assert_equal "perdida_total", L.mapear_estatus_cancelacion("perdida tot")
    assert_equal "cancelada", L.mapear_estatus_cancelacion("cancelada por falta de pago")
  end
end
