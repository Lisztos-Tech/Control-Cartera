require "test_helper"

class ClienteTest < ActiveSupport::TestCase
  test "requiere nombre" do
    cliente = Cliente.new
    assert_not cliente.valid?
    assert cliente.errors[:nombre].any?
  end

  test "buscar ignora acentos y mayúsculas" do
    cliente = Cliente.create!(nombre: "JOSÉ RAMÍREZ")
    assert_includes Cliente.buscar("jose ramirez"), cliente
    assert_includes Cliente.buscar("RAMÍREZ"), cliente
  end

  test "normalizar_nombre quita acentos, colapsa espacios y pone mayúsculas" do
    assert_equal "JOSE RAMIREZ", Cliente.normalizar_nombre("  José   Ramírez  ")
  end

  test "no se puede borrar cliente con pólizas" do
    assert_not clientes(:juan).destroy
  end

  test "polizas_vigentes excluye canceladas" do
    assert_not_includes clientes(:juan).polizas_vigentes, polizas(:cancelada_juan)
    assert_includes clientes(:juan).polizas_vigentes, polizas(:auto_juan)
  end
end
