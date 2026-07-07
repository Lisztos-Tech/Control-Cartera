module Importador
  # Acumula el resultado del import y lo imprime al final:
  # creados, flaggeados con motivo, ignorados con motivo y pares dudosos de clientes.
  class Reporte
    attr_reader :flaggeados, :ignoradas, :pares_dudosos, :reconciliacion

    def initialize
      @contadores = Hash.new(0)
      @flaggeados = []   # { hoja:, fila:, descripcion:, motivo: }
      @ignoradas = []    # { hoja:, fila:, motivo: }
      @pares_dudosos = [] # { nombre_a:, nombre_b:, similitud: }
      @reconciliacion = [] # { hoja:, numero_poliza:, detalle: }
    end

    def contar(clave, cantidad = 1)
      @contadores[clave] += cantidad
    end

    def [](clave)
      @contadores[clave]
    end

    def flag(hoja:, fila:, descripcion:, motivo:)
      @flaggeados << { hoja: hoja, fila: fila, descripcion: descripcion, motivo: motivo }
    end

    def ignorar(hoja:, fila:, motivo:)
      @ignoradas << { hoja: hoja, fila: fila, motivo: motivo }
      contar(:filas_ignoradas)
    end

    def par_dudoso(nombre_a, nombre_b, similitud)
      @pares_dudosos << { nombre_a: nombre_a, nombre_b: nombre_b, similitud: similitud.round(2) }
    end

    def reconciliar(hoja:, numero_poliza:, detalle:)
      @reconciliacion << { hoja: hoja, numero_poliza: numero_poliza, detalle: detalle }
    end

    def imprimir(io = $stdout)
      io.puts "\n========== RESUMEN DEL IMPORT =========="
      io.puts "Clientes creados:    #{self[:clientes_creados]}"
      io.puts "Pólizas creadas:     #{self[:polizas_creadas]}"
      io.puts "Recibos creados:     #{self[:recibos_creados]}"
      io.puts "Comisiones creadas:  #{self[:comisiones_creadas]}"
      io.puts "Filas ignoradas:     #{self[:filas_ignoradas]}"
      io.puts "Pólizas flaggeadas:  #{@flaggeados.size}"

      if @flaggeados.any?
        io.puts "\n--- Necesitan revisión ---"
        @flaggeados.each do |f|
          io.puts "  [#{f[:hoja]} fila #{f[:fila]}] #{f[:descripcion]}: #{f[:motivo]}"
        end
      end

      if @ignoradas.any?
        io.puts "\n--- Filas ignoradas ---"
        @ignoradas.each { |i| io.puts "  [#{i[:hoja]} fila #{i[:fila]}] #{i[:motivo]}" }
      end

      if @pares_dudosos.any?
        io.puts "\n--- Posibles clientes duplicados (NO fusionados, revisar a mano) ---"
        @pares_dudosos.each do |p|
          io.puts "  #{p[:nombre_a]}  <->  #{p[:nombre_b]}  (similitud #{p[:similitud]})"
        end
      end

      if @reconciliacion.any?
        io.puts "\n--- Reconciliación Hoja1/Hoja3/Hoja4 (pólizas no encontradas en hojas primarias) ---"
        @reconciliacion.each do |r|
          io.puts "  [#{r[:hoja]}] #{r[:numero_poliza]} — #{r[:detalle]}"
        end
      end

      io.puts "========================================\n"
    end
  end
end
