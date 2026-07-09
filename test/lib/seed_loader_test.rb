require "test_helper"
require Rails.root.join("lib/seed_loader")

class SeedLoaderTest < ActiveSupport::TestCase
  test "archivos de datos versionados existen con conteos esperados" do
    assert SeedLoader.data_present?

    assert_equal 248, YAML.load_file(Rails.root.join("db/seeds/data/clientes.yml")).size
    assert_equal 381, YAML.load_file(Rails.root.join("db/seeds/data/polizas.yml")).size
    assert_equal 323, YAML.load_file(Rails.root.join("db/seeds/data/recibos.yml")).size
    assert_equal 134, YAML.load_file(Rails.root.join("db/seeds/data/comisiones.yml")).size
  end

  test "carga registros desde yaml en bd vacía" do
    Comision.delete_all
    Recibo.delete_all
    Poliza.delete_all
    Cliente.delete_all

    assert SeedLoader.load!(reset: false)
    assert_equal 248, Cliente.count
    assert_equal 381, Poliza.count
    assert_equal 323, Recibo.count
    assert_equal 134, Comision.count
  end
end
