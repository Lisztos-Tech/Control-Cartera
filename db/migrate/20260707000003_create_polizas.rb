class CreatePolizas < ActiveRecord::Migration[8.0]
  def change
    create_table :polizas do |t|
      t.references :cliente, null: false, foreign_key: true
      t.string :numero_poliza
      t.string :aseguradora, null: false
      t.string :canal, null: false
      t.string :broker
      t.string :clave_agente
      t.string :ramo, null: false
      t.string :cobertura
      t.string :forma_pago, null: false
      t.decimal :prima_total, precision: 12, scale: 2
      t.string :moneda, null: false, default: "mxn"
      t.string :detalle_bien
      t.string :estatus, null: false, default: "vigente"
      t.text :motivo_cancelacion
      t.text :notas
      t.boolean :necesita_revision, null: false, default: false
      t.text :motivo_revision

      t.timestamps
    end

    add_index :polizas, :numero_poliza
    add_index :polizas, :estatus
    add_index :polizas, :necesita_revision
  end
end
