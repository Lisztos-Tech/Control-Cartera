class CreateClientes < ActiveRecord::Migration[8.0]
  def change
    create_table :clientes do |t|
      t.string :nombre, null: false
      t.string :telefono
      t.string :email
      t.text :notas

      t.timestamps
    end

    add_index :clientes, :nombre
    add_index :clientes, :nombre, using: :gin, opclass: :gin_trgm_ops, name: "index_clientes_on_nombre_trgm"
  end
end
