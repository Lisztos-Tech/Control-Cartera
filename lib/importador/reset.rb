module Importador
  # Borra clientes, pólizas, recibos y comisiones (no toca usuarios ni sesiones).
  module Reset
    module_function

    def limpiar!
      Comision.delete_all
      Recibo.delete_all
      Poliza.delete_all
      Cliente.delete_all
    end
  end
end
