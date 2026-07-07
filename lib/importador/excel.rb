require "roo"
require_relative "limpieza"
require_relative "reporte"

module Importador
  # Importador del archivo COMISIONES-IRMA.xlsx.
  # Migración de una sola vez: pensado para correr contra BD vacía (destroy + reimport),
  # no para sincronización incremental.
  class Excel
    L = Limpieza

    UMBRAL_FUSION = 0.93   # similitud trigram para considerar el mismo cliente
    UMBRAL_DUDOSO = 0.50   # por arriba de esto (y debajo de fusión) se reporta el par

    HOJAS_VENCIMIENTOS = {
      "VENCIMIENTOS INBURSA" => { aseguradora: "inbursa", canal: "directo" },
      "VENC QUALITAS" => { aseguradora: "qualitas", canal: "directo" }
    }.freeze

    ASEGURADORAS_CIA = {
      /QUALITAS|QUÁLITAS/i => "qualitas",
      /ANA/i => "ana_seguros",
      /ATLAS/i => "seguros_atlas",
      /INBURSA/i => "inbursa"
    }.freeze

    BROKERS = {
      /CANO/i => "cano",
      /CARMONA/i => "carmona"
    }.freeze

    attr_reader :reporte

    def initialize(path, reporte: Reporte.new)
      @path = path
      @reporte = reporte
      @clientes_por_nombre = {} # nombre normalizado => Cliente
    end

    def importar!
      @libro = Roo::Excelx.new(@path)

      HOJAS_VENCIMIENTOS.each do |hoja, defaults|
        con_hoja(hoja) { importar_vencimientos(hoja, **defaults) }
      end
      con_hoja("VENC QS BROKER") { importar_broker("VENC QS BROKER") }
      con_hoja("POLIZAS VIDA") { importar_vida("POLIZAS VIDA") }
      con_hoja("POL CANCELADAS") { importar_canceladas("POL CANCELADAS") }
      con_hoja("FORM PAGO COMI QS") { importar_comisiones("FORM PAGO COMI QS") }

      %w[Hoja1 Hoja3 Hoja4].each { |hoja| con_hoja(hoja, opcional: true) { reconciliar(hoja) } }

      reporte
    end

    private

    def con_hoja(nombre, opcional: false)
      unless @libro.sheets.include?(nombre)
        reporte.ignorar(hoja: nombre, fila: "-", motivo: "hoja no encontrada en el archivo") unless opcional
        return
      end
      yield
    end

    def filas(hoja)
      sheet = @libro.sheet(hoja)
      (sheet.first_row..sheet.last_row).map do |num|
        [ num, (1..sheet.last_column).map { |col| sheet.cell(num, col) } ]
      end
    end

    # ---- Hojas de vencimientos directos (Inbursa / Quálitas) ----
    # Col A=clave_agente, B=numero_poliza, C=contratante, D=vencimiento,
    # E=importe, F=forma_pago, G=ramo, H=plan/cobertura, resto=detalle y notas.
    def importar_vencimientos(hoja, aseguradora:, canal:)
      seccion_vrim = false

      filas(hoja).each do |num, celdas|
        next if fila_vacia?(celdas)
        next if fila_header?(celdas)

        texto_fila = celdas.map { |c| c.to_s }.join(" ")
        if texto_fila.match?(/TARJETAS?\s+VRIM/i)
          seccion_vrim = true
          next
        end

        if seccion_vrim
          importar_fila_vrim(hoja, num, celdas)
          next
        end

        clave, numero, contratante, vencimiento, importe, forma, ramo, cobertura, *resto = celdas

        procesar_fila_poliza(
          hoja: hoja, fila: num,
          contratante: contratante,
          numero_poliza: L.texto_celda(numero),
          aseguradora: aseguradora, canal: canal, broker: nil,
          clave_agente: L.texto_celda(clave),
          ramo: L.mapear_ramo(ramo) || "otro",
          cobertura: L.texto_celda(cobertura),
          forma_pago: L.mapear_forma_pago(forma),
          moneda: "mxn",
          vencimiento: vencimiento,
          importe: importe,
          detalle_bien: resto.map { |c| L.texto_celda(c) }.compact.join(" | ").presence
        )
      end
    end

    # ---- VENC QS BROKER: columnas por header (CIA = aseguradora real, AGENTE = broker) ----
    def importar_broker(hoja)
      todas = filas(hoja)
      header_idx = todas.index { |_, celdas| fila_header?(celdas) }
      unless header_idx
        reporte.ignorar(hoja: hoja, fila: "-", motivo: "no se encontró fila de encabezados")
        return
      end

      columnas = mapear_columnas(todas[header_idx][1])

      todas[(header_idx + 1)..].each do |num, celdas|
        next if fila_vacia?(celdas) || fila_header?(celdas)

        cia = L.texto_celda(celdas[columnas[:cia]]) if columnas[:cia]
        agente = L.texto_celda(celdas[columnas[:agente]]) if columnas[:agente]

        procesar_fila_poliza(
          hoja: hoja, fila: num,
          contratante: valor(celdas, columnas, :contratante),
          numero_poliza: L.texto_celda(valor(celdas, columnas, :numero_poliza)),
          aseguradora: mapear_aseguradora(cia) || "qualitas",
          canal: "broker",
          broker: mapear_broker(agente),
          clave_agente: nil,
          ramo: L.mapear_ramo(valor(celdas, columnas, :ramo)) || "otro",
          cobertura: L.texto_celda(valor(celdas, columnas, :cobertura)),
          forma_pago: L.mapear_forma_pago(valor(celdas, columnas, :forma_pago)),
          moneda: "mxn",
          vencimiento: valor(celdas, columnas, :vencimiento),
          importe: valor(celdas, columnas, :importe),
          detalle_bien: L.texto_celda(valor(celdas, columnas, :detalle)),
          aseguradora_desconocida: cia.present? && mapear_aseguradora(cia).nil?
        )
      end
    end

    # ---- POLIZAS VIDA: todo viene como string, moneda NACIONAL/DOLARES ----
    def importar_vida(hoja)
      todas = filas(hoja)
      header_idx = todas.index { |_, celdas| fila_header?(celdas) } || 0
      columnas = mapear_columnas(todas[header_idx][1])

      todas[(header_idx + 1)..].each do |num, celdas|
        next if fila_vacia?(celdas) || fila_header?(celdas)

        procesar_fila_poliza(
          hoja: hoja, fila: num,
          contratante: valor(celdas, columnas, :contratante),
          numero_poliza: L.texto_celda(valor(celdas, columnas, :numero_poliza)),
          aseguradora: "inbursa",
          canal: "directo",
          broker: nil,
          clave_agente: L.texto_celda(valor(celdas, columnas, :clave)),
          ramo: "vida",
          cobertura: L.texto_celda(valor(celdas, columnas, :cobertura)),
          forma_pago: L.mapear_forma_pago(valor(celdas, columnas, :forma_pago)),
          moneda: L.mapear_moneda(valor(celdas, columnas, :moneda)),
          vencimiento: valor(celdas, columnas, :vencimiento),
          importe: valor(celdas, columnas, :importe),
          detalle_bien: nil
        )
      end
    end

    # ---- POL CANCELADAS: estatus derivado del texto del motivo ----
    def importar_canceladas(hoja)
      todas = filas(hoja)
      header_idx = todas.index { |_, celdas| fila_header?(celdas) } || 0
      columnas = mapear_columnas(todas[header_idx][1])

      todas[(header_idx + 1)..].each do |num, celdas|
        next if fila_vacia?(celdas) || fila_header?(celdas)

        motivo = L.texto_celda(valor(celdas, columnas, :motivo)) ||
                 celdas.map { |c| L.texto_celda(c) }.compact.select { |t| t.match?(/cancel|renov|robo|\bPT\b|perdida|pérdida/i) }.join(" | ").presence

        procesar_fila_poliza(
          hoja: hoja, fila: num,
          contratante: valor(celdas, columnas, :contratante),
          numero_poliza: L.texto_celda(valor(celdas, columnas, :numero_poliza)),
          aseguradora: mapear_aseguradora(L.texto_celda(valor(celdas, columnas, :cia))) || "otra",
          canal: "directo",
          broker: nil,
          clave_agente: nil,
          ramo: L.mapear_ramo(valor(celdas, columnas, :ramo)) || "otro",
          cobertura: nil,
          forma_pago: L.mapear_forma_pago(valor(celdas, columnas, :forma_pago)),
          moneda: "mxn",
          vencimiento: nil, # cancelada: sin recibos pendientes
          importe: nil,
          detalle_bien: L.texto_celda(valor(celdas, columnas, :detalle)),
          estatus: L.mapear_estatus_cancelacion(motivo),
          motivo_cancelacion: motivo
        )
      end
    end

    # ---- FORM PAGO COMI QS: varias tablas apiladas con headers repetidos ----
    def importar_comisiones(hoja)
      columnas = nil

      filas(hoja).each do |num, celdas|
        next if fila_vacia?(celdas)

        if fila_header_comisiones?(celdas)
          columnas = mapear_columnas(celdas)
          next
        end
        next unless columnas

        numero = L.texto_celda(valor(celdas, columnas, :numero_poliza))
        nombre = L.texto_celda(valor(celdas, columnas, :contratante))
        next if numero.blank? && nombre.blank?

        poliza = encontrar_poliza(numero, nombre)
        unless poliza
          reporte.ignorar(hoja: hoja, fila: num,
                          motivo: "no se pudo vincular a una póliza (##{numero || 's/n'} #{nombre})")
          next
        end

        fecha_res = L.parsear_fecha(valor(celdas, columnas, :fecha))
        prima_res = L.parsear_importe(valor(celdas, columnas, :prima_neta))
        monto_res = L.parsear_importe(valor(celdas, columnas, :comision))
        porcentaje = parsear_porcentaje(valor(celdas, columnas, :porcentaje))

        recibo = recibo_para_comision(poliza, fecha_res&.fecha)
        if recibo.comision
          reporte.ignorar(hoja: hoja, fila: num, motivo: "el recibo ya tiene comisión (póliza #{poliza.numero_poliza})")
          next
        end

        recibo.create_comision!(
          prima_neta: prima_res&.importe,
          porcentaje: porcentaje,
          monto: monto_res&.importe,
          estatus: "por_cobrar"
        )
        reporte.contar(:comisiones_creadas)

        flaggear(poliza, hoja, num, "fecha ambigua en hoja de comisiones (#{L.texto_celda(valor(celdas, columnas, :fecha))})") if fecha_res&.ambigua
      end
    end

    # ---- Reconciliación de hojas secundarias (Hoja1/Hoja3/Hoja4): solo reportar ----
    def reconciliar(hoja)
      numeros_existentes = Poliza.where.not(numero_poliza: nil).pluck(:numero_poliza).to_set

      filas(hoja).each do |_num, celdas|
        celdas.each do |celda|
          texto = L.texto_celda(celda)
          next unless texto&.match?(/\A[A-Z0-9-]{6,20}\z/i) && texto.match?(/\d{4}/)
          next if numeros_existentes.include?(texto)
          next if reporte.reconciliacion.any? { |r| r[:numero_poliza] == texto }

          reporte.reconciliar(hoja: hoja, numero_poliza: texto,
                              detalle: "aparece en #{hoja} pero no en las hojas primarias")
        end
      end
    end

    # ---- Núcleo: crear/consolidar póliza + recibo a partir de una fila ----
    def procesar_fila_poliza(hoja:, fila:, contratante:, numero_poliza:, aseguradora:, canal:,
                             broker:, clave_agente:, ramo:, cobertura:, forma_pago:, moneda:,
                             vencimiento:, importe:, detalle_bien:, estatus: "vigente",
                             motivo_cancelacion: nil, aseguradora_desconocida: false)
      nombre_res = L.separar_nombre(contratante)
      if nombre_res.nombre.blank?
        reporte.ignorar(hoja: hoja, fila: fila, motivo: "fila sin nombre de contratante")
        return
      end

      cliente = encontrar_o_crear_cliente(nombre_res.nombre)

      fecha_res = L.parsear_fecha(vencimiento)
      importe_res = L.parsear_importe(importe)

      notas = [ nombre_res.notas, importe_res&.texto ].compact.join(" | ").presence

      poliza = poliza_existente(cliente, numero_poliza, aseguradora)

      if poliza
        consolidar_poliza(poliza, hoja, fila, notas: notas, detalle_bien: detalle_bien,
                          forma_pago: forma_pago, cobertura: cobertura)
      else
        poliza = cliente.polizas.create!(
          numero_poliza: numero_poliza,
          aseguradora: aseguradora,
          canal: canal,
          broker: broker,
          clave_agente: clave_agente,
          ramo: ramo,
          cobertura: cobertura,
          forma_pago: forma_pago || "anual",
          moneda: moneda,
          detalle_bien: detalle_bien,
          estatus: estatus,
          motivo_cancelacion: motivo_cancelacion,
          notas: notas
        )
        reporte.contar(:polizas_creadas)
        @polizas_por_numero = nil # invalidar cache

        flaggear(poliza, hoja, fila, "sin forma de pago legible; se asumió anual") if forma_pago.blank?
        flaggear(poliza, hoja, fila, "aseguradora (CIA) no reconocida") if aseguradora_desconocida
      end

      if importe_res&.texto
        flaggear(poliza, hoja, fila, "importe ilegible (\"#{importe_res.texto}\"); se movió a notas")
      end

      if vencimiento.present? && fecha_res.nil?
        flaggear(poliza, hoja, fila, "fecha de vencimiento ilegible (\"#{L.texto_celda(vencimiento)}\")")
      end

      if fecha_res
        crear_recibo(poliza, fecha_res, importe_res&.importe, hoja, fila)
      end

      poliza
    end

    def crear_recibo(poliza, fecha_res, importe, hoja, fila)
      # Misma fecha = fila duplicada de renovación ya consolidada; no duplicar recibo.
      return if poliza.recibos.exists?(fecha_vencimiento: fecha_res.fecha)

      poliza.recibos.create!(fecha_vencimiento: fecha_res.fecha, importe: importe, estatus: "pendiente")
      reporte.contar(:recibos_creados)

      flaggear(poliza, hoja, fila, "fecha ambigua (¿día/mes o mes/día?): #{fecha_res.fecha.strftime('%d/%m/%Y')}") if fecha_res.ambigua
    end

    # Regla 5: filas repetidas del mismo número de póliza son recibos futuros.
    # Si difieren en otros campos, conservar la versión con más datos y flaggear.
    def consolidar_poliza(poliza, hoja, fila, notas:, detalle_bien:, forma_pago:, cobertura:)
      poliza.notas = [ poliza.notas, notas ].compact.join(" | ").presence if notas

      diferencias = []
      diferencias << "detalle_bien" if detalle_bien.present? && poliza.detalle_bien.present? && detalle_bien != poliza.detalle_bien
      diferencias << "forma_pago" if forma_pago.present? && poliza.forma_pago != forma_pago
      diferencias << "cobertura" if cobertura.present? && poliza.cobertura.present? && cobertura != poliza.cobertura

      poliza.detalle_bien ||= detalle_bien
      poliza.cobertura ||= cobertura
      poliza.save!

      if diferencias.any?
        flaggear(poliza, hoja, fila, "filas duplicadas con datos distintos (#{diferencias.join(', ')})")
      end
    end

    def poliza_existente(cliente, numero_poliza, aseguradora)
      if numero_poliza.present?
        Poliza.find_by(numero_poliza: numero_poliza, aseguradora: aseguradora)
      else
        # Sin número: solo consolidar dentro del mismo cliente.
        cliente.polizas.find_by(numero_poliza: nil, aseguradora: aseguradora)
      end
    end

    # ---- Clientes: dedup por nombre normalizado + similitud trigram ----
    def encontrar_o_crear_cliente(nombre)
      normalizado = Cliente.normalizar_nombre(nombre)
      return @clientes_por_nombre[normalizado] if @clientes_por_nombre[normalizado]

      similar, similitud = mas_similar(normalizado)

      if similar && similitud >= UMBRAL_FUSION
        @clientes_por_nombre[normalizado] = similar
        return similar
      end

      cliente = Cliente.create!(nombre: nombre)
      reporte.contar(:clientes_creados)
      @clientes_por_nombre[normalizado] = cliente

      if similar && similitud >= UMBRAL_DUDOSO
        reporte.par_dudoso(similar.nombre, nombre, similitud)
      end

      cliente
    end

    def mas_similar(normalizado)
      mejor = nil
      mejor_sim = 0.0
      @clientes_por_nombre.each do |nombre_existente, cliente|
        sim = trigram_similitud(normalizado, nombre_existente)
        if sim > mejor_sim
          mejor = cliente
          mejor_sim = sim
        end
      end
      [ mejor, mejor_sim ]
    end

    def trigram_similitud(a, b)
      ta = trigramas(a)
      tb = trigramas(b)
      return 0.0 if ta.empty? || tb.empty?

      (ta & tb).size.to_f / (ta | tb).size
    end

    def trigramas(s)
      padded = "  #{s} "
      (0..padded.length - 3).map { |i| padded[i, 3] }.to_set
    end

    # ---- Vinculación de comisiones ----
    def encontrar_poliza(numero, nombre)
      if numero.present?
        poliza = Poliza.find_by(numero_poliza: numero)
        return poliza if poliza
      end

      return nil if nombre.blank?

      normalizado = Cliente.normalizar_nombre(L.separar_nombre(nombre).nombre.to_s)
      cliente = @clientes_por_nombre[normalizado]
      unless cliente
        candidato, sim = mas_similar(normalizado)
        cliente = candidato if sim >= UMBRAL_FUSION
      end
      cliente&.polizas&.order(:created_at)&.last
    end

    def recibo_para_comision(poliza, fecha)
      if fecha
        cercano = poliza.recibos.min_by { |r| (r.fecha_vencimiento - fecha).abs }
        return cercano if cercano && !cercano.comision
      end
      sin_comision = poliza.recibos.detect { |r| r.comision.nil? }
      return sin_comision if sin_comision

      recibo = poliza.recibos.create!(
        fecha_vencimiento: fecha || Date.current,
        estatus: fecha ? "pagado" : "pendiente",
        fecha_pago: fecha
      )
      reporte.contar(:recibos_creados)
      recibo
    end

    def parsear_porcentaje(valor)
      res = L.parsear_importe(valor)
      return nil unless res&.importe

      pct = res.importe
      pct < 1 ? (pct * 100).round(2) : pct # 0.08 => 8%
    end

    # ---- Utilidades de filas y headers ----
    def fila_vacia?(celdas)
      celdas.all? { |c| L.texto_celda(c).blank? }
    end

    HEADER_KEYWORDS = /\A(CLAVE|AGENTE|P[OÓ]LIZA|No\.? ?DE ?P[OÓ]LIZA|CONTRATANTE|ASEGURADO|NOMBRE|VENC|FECHA|IMPORTE|PRIMA|FORMA|RAMO|TIPO|PLAN|COBERTURA|CIA|C[IÍ]A|MONEDA|MOTIVO|DETALLE|VEH[IÍ]CULO|DESCRIPCI[OÓ]N|%|COMI)/i

    def fila_header?(celdas)
      textos = celdas.map { |c| L.texto_celda(c) }.compact
      return false if textos.size < 2

      coincidencias = textos.count { |t| t.match?(HEADER_KEYWORDS) }
      coincidencias >= [ textos.size / 2, 2 ].max
    end

    def fila_header_comisiones?(celdas)
      textos = celdas.map { |c| L.texto_celda(c) }.compact.join(" ")
      textos.match?(/FECHA ENV/i) && textos.match?(/P[OÓ]LIZA/i)
    end

    COLUMNAS = {
      clave: /\ACLAVE/i,
      numero_poliza: /P[OÓ]LIZA/i,
      contratante: /CONTRATANTE|ASEGURADO|NOMBRE/i,
      vencimiento: /VENC|VIGENCIA/i,
      fecha: /\AFECHA/i,
      importe: /IMPORTE|PRIMA TOTAL|\APRIMA\z/i,
      prima_neta: /PRIMA ?NETA/i,
      forma_pago: /FORMA|PAGO/i,
      ramo: /RAMO|TIPO/i,
      cobertura: /PLAN|COBERTURA/i,
      cia: /\AC[IÍ]A\.?\z|ASEGURADORA/i,
      agente: /\AAGENTE\z|BROKER/i,
      moneda: /MONEDA/i,
      motivo: /MOTIVO|OBSERV/i,
      detalle: /DETALLE|VEH[IÍ]CULO|DESCRIPCI[OÓ]N|BIEN/i,
      porcentaje: /%|PORC/i,
      comision: /COMISI[OÓ]N|COMI\b/i
    }.freeze

    def mapear_columnas(celdas_header)
      columnas = {}
      celdas_header.each_with_index do |celda, idx|
        texto = L.texto_celda(celda)
        next if texto.blank?

        COLUMNAS.each do |clave, regex|
          columnas[clave] = idx if columnas[clave].nil? && texto.match?(regex)
        end
      end
      # prima_neta tiene prioridad sobre importe si el header dice "PRIMA NETA"
      columnas.delete(:importe) if columnas[:importe] && columnas[:importe] == columnas[:prima_neta]
      columnas
    end

    def valor(celdas, columnas, clave)
      idx = columnas[clave]
      idx ? celdas[idx] : nil
    end

    def mapear_aseguradora(texto)
      return nil if texto.blank?

      ASEGURADORAS_CIA.each { |regex, aseg| return aseg if texto.match?(regex) }
      nil
    end

    def mapear_broker(texto)
      return nil if texto.blank?

      BROKERS.each { |regex, broker| return broker if texto.match?(regex) }
      nil
    end

    def flaggear(poliza, hoja, fila, motivo)
      motivos = [ poliza.motivo_revision, motivo ].compact.uniq.join(" | ")
      poliza.update!(necesita_revision: true, motivo_revision: motivos)
      reporte.flag(hoja: hoja, fila: fila,
                   descripcion: "#{poliza.cliente.nombre} ##{poliza.numero_poliza || 's/n'}",
                   motivo: motivo)
    end

    # ---- Sección VRIM al pie de VENCIMIENTOS INBURSA ----
    def importar_fila_vrim(hoja, num, celdas)
      nombre = celdas.map { |c| L.texto_celda(c) }.compact.first
      return if nombre.blank?

      cliente = @cliente_vrim ||= begin
        reporte.contar(:clientes_creados)
        Cliente.create!(nombre: "PENDIENTES VRIM", notas: "Cliente ficticio: nombres de la sección TARJETAS VRIM del Excel")
      end
      cliente.update!(notas: [ cliente.notas, nombre ].compact.join("\n"))
      reporte.contar(:nombres_vrim)
    end
  end
end
