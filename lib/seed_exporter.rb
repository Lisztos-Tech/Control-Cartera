require "yaml"

class SeedExporter
  DATA_DIR = Rails.root.join("db/seeds/data").freeze

  ATTRIBUTES = {
    "Cliente" => %w[nombre telefono email notas],
    "Poliza" => %w[cliente_id numero_poliza aseguradora canal broker clave_agente ramo cobertura
                   forma_pago prima_total moneda detalle_bien estatus motivo_cancelacion notas
                   necesita_revision motivo_revision observaciones],
    "Recibo" => %w[poliza_id numero_recibo fecha_vencimiento importe fecha_pago estatus],
    "Comision" => %w[recibo_id prima_neta porcentaje monto estatus fecha_cobro notas]
  }.freeze

  def self.dump!
    DATA_DIR.mkpath

    self.export_model(Cliente, "clientes.yml")
    self.export_model(Poliza, "polizas.yml")
    self.export_model(Recibo, "recibos.yml")
    self.export_model(Comision, "comisiones.yml")

    puts "Exportado a #{DATA_DIR}/"
    puts "  #{Cliente.count} clientes, #{Poliza.count} pólizas, #{Recibo.count} recibos, #{Comision.count} comisiones"
  end

  def self.export_model(klass, filename)
    attrs = ATTRIBUTES.fetch(klass.name)
    records = klass.order(:id).map do |record|
      { "id" => record.id }.merge(
        attrs.index_with { |name| self.serialize_value(record.public_send(name)) }
      )
    end

    File.write(DATA_DIR.join(filename), records.to_yaml)
  end

  def self.serialize_value(value)
    case value
    when BigDecimal then value.to_s("F")
    when Date, Time, ActiveSupport::TimeWithZone then value.iso8601
    else value
    end
  end
end
