require "yaml"

class SeedLoader
  DATA_DIR = Rails.root.join("db/seeds/data").freeze

  MODELS = [
    [ Cliente, "clientes.yml" ],
    [ Poliza, "polizas.yml" ],
    [ Recibo, "recibos.yml" ],
    [ Comision, "comisiones.yml" ]
  ].freeze

  FK = {
    "Poliza" => "cliente_id",
    "Recibo" => "poliza_id",
    "Comision" => "recibo_id"
  }.freeze

  def self.data_present?
    DATA_DIR.join("clientes.yml").exist?
  end

  def self.load!(reset: false)
    abort "Faltan archivos en db/seeds/data/. Corre bin/rails seed:dump con la BD cargada." unless data_present?

    if Poliza.exists? && !reset
      puts "Ya hay datos (#{Cliente.count} clientes, #{Poliza.count} pólizas); seeds omitidos."
      puts "Usa LIMPIAR=1 bin/rails db:seed para borrar y volver a cargar."
      return false
    end

    clear! if reset

    id_maps = {}
    MODELS.each do |klass, filename|
      records = YAML.load_file(DATA_DIR.join(filename))
      id_maps[klass.name] = import_records(klass, records, id_maps)
    end

    reset_sequences!
    true
  end

  def self.clear!
    Comision.delete_all
    Recibo.delete_all
    Poliza.delete_all
    Cliente.delete_all
  end

  def self.import_records(klass, records, id_maps)
    fk = FK[klass.name]
    parent_map = case klass.name
    when "Poliza" then id_maps.fetch("Cliente")
    when "Recibo" then id_maps.fetch("Poliza")
    when "Comision" then id_maps.fetch("Recibo")
    else {}
    end

    records.each_with_object({}) do |row, map|
      attrs = row.stringify_keys
      old_id = attrs.delete("id")

      if fk
        old_fk = attrs.fetch(fk)
        attrs[fk] = parent_map.fetch(old_fk) { raise "FK #{fk}=#{old_fk} sin mapeo al crear #{klass.name} ##{old_id}" }
      end

      record = klass.create!(deserialize_attrs(attrs))
      map[old_id] = record.id
    end
  end

  def self.reset_sequences!
    %w[clientes polizas recibos comisiones].each do |table|
      ActiveRecord::Base.connection.reset_pk_sequence!(table)
    end
  end

  def self.deserialize_attrs(attrs)
    attrs.transform_values do |value|
      next value if value.nil?

      case value
      when String
        if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          Date.iso8601(value)
        elsif value.match?(/\A\d{4}-\d{2}-\d{2}T/)
          Time.zone.parse(value)
        elsif value.match?(/\A-?\d+\.\d+\z/)
          BigDecimal(value)
        else
          value
        end
      else
        value
      end
    end
  end
end
