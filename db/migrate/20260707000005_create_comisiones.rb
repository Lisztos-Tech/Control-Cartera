class CreateComisiones < ActiveRecord::Migration[8.0]
  def change
    create_table :comisiones do |t|
      t.references :recibo, null: false, foreign_key: true, index: { unique: true }
      t.decimal :prima_neta, precision: 12, scale: 2
      t.decimal :porcentaje, precision: 5, scale: 2
      t.decimal :monto, precision: 12, scale: 2
      t.string :estatus, null: false, default: "por_cobrar"
      t.date :fecha_cobro
      t.text :notas

      t.timestamps
    end

    add_index :comisiones, :estatus
  end
end
