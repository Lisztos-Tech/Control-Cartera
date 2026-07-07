class CreateRecibos < ActiveRecord::Migration[8.0]
  def change
    create_table :recibos do |t|
      t.references :poliza, null: false, foreign_key: true
      t.string :numero_recibo
      t.date :fecha_vencimiento, null: false
      t.decimal :importe, precision: 12, scale: 2
      t.date :fecha_pago
      t.string :estatus, null: false, default: "pendiente"

      t.timestamps
    end

    add_index :recibos, :fecha_vencimiento
    add_index :recibos, :estatus
  end
end
