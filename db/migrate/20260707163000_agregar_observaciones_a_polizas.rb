class AgregarObservacionesAPolizas < ActiveRecord::Migration[8.0]
  def up
    add_column :polizas, :observaciones, :text

    # El importador juntaba el bien y las notas extra del Excel en detalle_bien
    # separados por " | ". Separarlos: la primera parte es el bien, el resto
    # son observaciones.
    execute <<~SQL
      UPDATE polizas
      SET observaciones = substring(detalle_bien FROM position(' | ' IN detalle_bien) + 3),
          detalle_bien = substring(detalle_bien FROM 1 FOR position(' | ' IN detalle_bien) - 1)
      WHERE detalle_bien LIKE '% | %'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE polizas
      SET detalle_bien = detalle_bien || ' | ' || observaciones
      WHERE observaciones IS NOT NULL AND observaciones <> ''
    SQL
    remove_column :polizas, :observaciones
  end
end
