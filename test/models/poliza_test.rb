require "test_helper"

class PolizaTest < ActiveSupport::TestCase
  test "canal broker exige broker" do
    poliza = polizas(:auto_juan)
    poliza.canal = "broker"
    poliza.broker = nil
    assert_not poliza.valid?
    assert poliza.errors[:broker].any?
  end

  test "canal directo no admite broker" do
    poliza = polizas(:auto_juan)
    poliza.broker = "cano"
    assert_not poliza.valid?
  end

  test "proximo_vencimiento es el mínimo de los recibos pendientes" do
    assert_equal recibos(:vencido_juan).fecha_vencimiento, polizas(:auto_juan).proximo_vencimiento
  end

  test "proximo_vencimiento es nil sin recibos pendientes" do
    assert_nil polizas(:broker_maria).proximo_vencimiento
  end

  test "periodica? distingue contado" do
    assert polizas(:auto_juan).periodica?
    assert_not polizas(:broker_maria).periodica?
  end

  test "posible_duplicado? detecta mismo número y aseguradora" do
    otra = Poliza.new(polizas(:auto_juan).attributes.except("id", "created_at", "updated_at"))
    otra.save!
    assert otra.posible_duplicado?
    assert_not polizas(:vida_maria).posible_duplicado?
  end

  test "posible_duplicado? ignora números en blanco" do
    poliza = polizas(:auto_juan)
    poliza.update!(numero_poliza: nil)
    assert_not poliza.posible_duplicado?
  end

  test "buscar por nombre de cliente o número de póliza" do
    assert_includes Poliza.buscar("juan perez"), polizas(:auto_juan)
    assert_includes Poliza.buscar("Q-5544"), polizas(:broker_maria)
  end

  test "limpiar_revision! borra flag y motivo" do
    poliza = polizas(:auto_juan)
    poliza.update!(necesita_revision: true, motivo_revision: "fecha ambigua")
    poliza.limpiar_revision!
    assert_not poliza.necesita_revision
    assert_nil poliza.motivo_revision
  end

  test "scope no_vigentes" do
    assert_includes Poliza.no_vigentes, polizas(:cancelada_juan)
    assert_not_includes Poliza.no_vigentes, polizas(:auto_juan)
  end
end
