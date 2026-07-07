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

    # Columnas por posición (0-based) de cada hoja de vencimientos.
    # Los headers reales están desalineados de los datos, así que el layout
    # se fija por posición observada en el archivo real.
    LAYOUT_INBURSA = { clave: 0, numero: 1, contratante: 2, venc: 3, importe: 4,
                       forma: 5, ramo: 6, cobertura: 7, detalle: 8, extra: 9 }.freeze
    LAYOUT_QUALITAS = { numero: 0, contratante: 1, venc: 2, importe: 3,
                        forma: 4, ramo: 5, cia: 6, detalle: 8, extra: 9 }.freeze
    LAYOUT_BROKER = { numero: 0, contratante: 1, venc: 2, importe: 3, cia: 4,
                      forma: 5, cobertura: 6, detalle: 8, extra: 9, agente: 10 }.freeze
    LAYOUT_CANCELADAS = { clave: 0, numero: 1, contratante: 2, venc: 3, importe: 4,
                          forma: 5, ramo: 6 }.freeze

    ASEGURADORAS_CIA = {
      /QUALITAS|QUÁLITAS|\bQS\b/i => "qualitas",
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

      con_hoja("VENCIMIENTOS INBURSA") do
        importar_vencimientos("VENCIMIENTOS INBURSA", LAYOUT_INBURSA,
                              aseguradora: "inbursa", canal: "directo", vrim: true)
      end
      con_hoja("VENC QUALITAS") do
        importar_vencimientos("VENC QUALITAS", LAYOUT_QUALITAS,
                              aseguradora: "qualitas", canal: "directo")
      end
      con_hoja("VENC QS BROKER") do
        importar_vencimientos("VENC QS BROKER", LAYOUT_BROKER,
                              aseguradora: "qualitas", canal: "broker")
      end
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

    def celda(celdas, layout, clave)
      idx = layout[clave]
      idx ? celdas[idx] : nil
    end

    # ---- Hojas de vencimientos (Inbursa / Quálitas / Broker) ----
    def importar_vencimientos(hoja, layout, aseguradora:, canal:, vrim: false)
      seccion_vrim = false

      filas(hoja).each do |num, celdas|
        next if fila_vacia?(celdas)
        next if fila_header?(celdas)

        texto_fila = celdas.map { |c| c.to_s }.join(" ")
        if vrim && texto_fila.match?(/TARJETAS?\s+VRIM/i)
          seccion_vrim = true
          next
        end

        if seccion_vrim
          importar_fila_vrim(hoja, num, celdas)
          next
        end

        cia = L.texto_celda(celda(celdas, layout, :cia))
        agente = L.texto_celda(celda(celdas, layout, :agente))
        aseguradora_fila = canal == "broker" ? (mapear_aseguradora(cia) || aseguradora) : aseguradora

        # Columna "Observaciones" del Excel = el bien (FORD RANGER 2012…);
        # la columna extra sin nombre = notas sueltas → observaciones.
        detalle = L.texto_celda(celda(celdas, layout, :detalle))
        observaciones = L.texto_celda(celda(celdas, layout, :extra))

        procesar_fila_poliza(
          hoja: hoja, fila: num,
          contratante: celda(celdas, layout, :contratante),
          numero_poliza: L.texto_celda(celda(celdas, layout, :numero)),
          aseguradora: aseguradora_fila,
          canal: canal,
          broker: canal == "broker" ? mapear_broker(agente) : nil,
          clave_agente: L.texto_celda(celda(celdas, layout, :clave)),
          ramo: L.mapear_ramo(celda(celdas, layout, :ramo)) || "otro",
          cobertura: L.texto_celda(celda(celdas, layout, :cobertura)),
          forma_pago: L.mapear_forma_pago(celda(celdas, layout, :forma)),
          moneda: "mxn",
          vencimiento: celda(celdas, layout, :venc),
          importe: celda(celdas, layout, :importe),
          detalle_bien: detalle,
          observaciones: observaciones,
          aseguradora_desconocida: canal == "broker" && cia.present? && mapear_aseguradora(cia).nil?,
          broker_desconocido: canal == "broker" && agente.present? && mapear_broker(agente).nil?
        )
      end
    end

    # ---- POLIZAS VIDA: reporte de recibos de Inbursa, todo en strings ----
    # Headers reales: Emisor | Carpeta | Recibo | Importe | Moneda | Tipo Cobro |
    # Asegurado | Cliente | Fecha Efecto | Fecha Vencimiento | Fecha Pago | Comisión
    def importar_vida(hoja)
      todas = filas(hoja)
      header_idx = todas.index { |_, celdas| celdas.map { |c| c.to_s }.join(" ").match?(/Carpeta|Emisor/i) }
      unless header_idx
        reporte.ignorar(hoja: hoja, fila: "-", motivo: "no se encontró fila de encabezados (Emisor/Carpeta)")
        return
      end

      headers = todas[header_idx][1].map { |c| L.texto_celda(c).to_s }
      col = {
        clave: headers.index { |h| h.match?(/Emisor/i) },
        numero: headers.index { |h| h.match?(/Carpeta/i) },
        recibo: headers.index { |h| h.match?(/\ARecibo\z/i) },
        importe: headers.index { |h| h.match?(/Importe/i) },
        moneda: headers.index { |h| h.match?(/Moneda/i) },
        contratante: headers.index { |h| h.match?(/Asegurado/i) },
        efecto: headers.index { |h| h.match?(/Efecto/i) },
        venc: headers.index { |h| h.match?(/Vencimiento/i) },
        pago: headers.index { |h| h.match?(/Pago/i) && !h.match?(/Tipo/i) },
        comision: headers.index { |h| h.match?(/Comisi/i) }
      }

      todas[(header_idx + 1)..].each do |num, celdas|
        next if fila_vacia?(celdas)

        efecto = L.parsear_fecha(celdas[col[:efecto]]) if col[:efecto]
        venc = L.parsear_fecha(celdas[col[:venc]]) if col[:venc]
        forma = forma_por_periodo(efecto&.fecha, venc&.fecha)

        poliza = procesar_fila_poliza(
          hoja: hoja, fila: num,
          contratante: celdas[col[:contratante]],
          numero_poliza: L.texto_celda(celdas[col[:numero]]),
          aseguradora: "inbursa",
          canal: "directo",
          broker: nil,
          clave_agente: L.texto_celda(celdas[col[:clave]]),
          ramo: "vida",
          cobertura: nil,
          forma_pago: forma,
          moneda: L.mapear_moneda(celdas[col[:moneda]]),
          vencimiento: celdas[col[:venc]],
          importe: celdas[col[:importe]],
          detalle_bien: nil
        )
        next unless poliza

        # La fila es un recibo del reporte: si trae fecha de pago, quedó pagado.
        fecha_pago = L.parsear_fecha(celdas[col[:pago]])&.fecha if col[:pago]
        recibo = venc && poliza.recibos.find_by(fecha_vencimiento: venc.fecha)
        if recibo
          recibo.update!(numero_recibo: L.texto_celda(celdas[col[:recibo]]))
          recibo.update!(estatus: "pagado", fecha_pago: fecha_pago) if fecha_pago
        end

        # Comisión reportada por Inbursa en la misma fila (vida sí paga comisión).
        monto = L.parsear_importe(celdas[col[:comision]])&.importe if col[:comision]
        if recibo && monto&.positive? && recibo.comision.nil?
          recibo.create_comision!(
            monto: monto,
            estatus: fecha_pago ? "pagada" : "por_cobrar",
            fecha_cobro: fecha_pago
          )
          reporte.contar(:comisiones_creadas)
        end
      end
    end

    # ---- POL CANCELADAS: estatus derivado del texto; el motivo se junta de
    # las columnas de texto libre al final de la fila ----
    def importar_canceladas(hoja)
      filas(hoja).each do |num, celdas|
        next if fila_vacia?(celdas) || fila_header?(celdas)

        texto_libre = celdas[7..].to_a.map { |c| L.texto_celda(c) }.compact
        motivo = texto_libre.join(" | ").presence

        procesar_fila_poliza(
          hoja: hoja, fila: num,
          contratante: celda(celdas, LAYOUT_CANCELADAS, :contratante),
          numero_poliza: L.texto_celda(celda(celdas, LAYOUT_CANCELADAS, :numero)),
          aseguradora: mapear_aseguradora(texto_libre.join(" ")) || "inbursa",
          canal: "directo",
          broker: nil,
          clave_agente: L.texto_celda(celda(celdas, LAYOUT_CANCELADAS, :clave)),
          ramo: L.mapear_ramo(celda(celdas, LAYOUT_CANCELADAS, :ramo)) || "otro",
          cobertura: nil,
          forma_pago: L.mapear_forma_pago(celda(celdas, LAYOUT_CANCELADAS, :forma)),
          moneda: "mxn",
          vencimiento: nil, # cancelada: sin recibos pendientes
          importe: nil,
          detalle_bien: nil,
          estatus: L.mapear_estatus_cancelacion(motivo),
          motivo_cancelacion: motivo
        )
      end
    end

    # ---- FORM PAGO COMI QS: varias tablas apiladas con headers distintos.
    # Cada bloque arranca con una fila header que contiene PÓLIZA y PRIMA/COMISIÓN;
    # las columnas se mapean por nombre dentro de cada bloque. ----
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
        next if numero.blank? && !nombre.match?(/\p{Lu}{2,}/) # subtotales y ruido

        cia = mapear_aseguradora(L.texto_celda(valor(celdas, columnas, :cia)))
        poliza = encontrar_poliza(numero, nombre, aseguradora: cia)
        unless poliza
          reporte.ignorar(hoja: hoja, fila: num,
                          motivo: "no se pudo vincular a una póliza (##{numero || 's/n'} #{nombre})")
          next
        end

        fecha_pago = L.parsear_fecha(valor(celdas, columnas, :fecha_pago))
        prima_res = L.parsear_importe(valor(celdas, columnas, :prima_neta) || valor(celdas, columnas, :importe))
        monto_res = L.parsear_importe(valor(celdas, columnas, :comision))
        porcentaje = parsear_porcentaje(valor(celdas, columnas, :porcentaje))

        recibo = recibo_para_comision(poliza, fecha_pago&.fecha)
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

        if fecha_pago&.ambigua
          flaggear(poliza, hoja, num, "fecha ambigua en hoja de comisiones (#{L.texto_celda(valor(celdas, columnas, :fecha_pago))})")
        end
      end
    end

    # ---- Reconciliación de hojas secundarias (Hoja1/Hoja3/Hoja4): solo reportar.
    # Se identifica la columna de números de póliza (la que más celdas tipo
    # póliza tenga) para no confundir teléfonos u otros números sueltos. ----
    def reconciliar(hoja)
      numeros_existentes = Poliza.where.not(numero_poliza: nil).pluck(:numero_poliza).to_set
      todas = filas(hoja)

      conteo_por_columna = Hash.new(0)
      todas.each do |_num, celdas|
        celdas.each_with_index do |celda, idx|
          conteo_por_columna[idx] += 1 if numero_poliza?(L.texto_celda(celda))
        end
      end
      col_poliza, coincidencias = conteo_por_columna.max_by { |_, v| v }
      return if coincidencias.to_i < 3 # sin columna clara de pólizas, no adivinar

      todas.each do |_num, celdas|
        texto = L.texto_celda(celdas[col_poliza])
        next unless numero_poliza?(texto)
        next if numeros_existentes.include?(texto)
        next if reporte.reconciliacion.any? { |r| r[:numero_poliza] == texto }

        reporte.reconciliar(hoja: hoja, numero_poliza: texto,
                            detalle: "aparece en #{hoja} pero no en las hojas primarias")
      end
    end

    def numero_poliza?(texto)
      texto.present? && texto.match?(/\A\d{6,12}\z/)
    end

    # ---- Núcleo: crear/consolidar póliza + recibo a partir de una fila ----
    def procesar_fila_poliza(hoja:, fila:, contratante:, numero_poliza:, aseguradora:, canal:,
                             broker:, clave_agente:, ramo:, cobertura:, forma_pago:, moneda:,
                             vencimiento:, importe:, detalle_bien:, observaciones: nil,
                             estatus: "vigente", motivo_cancelacion: nil,
                             aseguradora_desconocida: false, broker_desconocido: false)
      nombre_res = L.separar_nombre(contratante)
      if nombre_res.nombre.blank?
        reporte.ignorar(hoja: hoja, fila: fila, motivo: "fila sin nombre de contratante")
        return nil
      end

      cliente = encontrar_o_crear_cliente(nombre_res.nombre)

      fecha_res = L.parsear_fecha(vencimiento)
      importe_res = L.parsear_importe(importe)

      notas = [ nombre_res.notas, importe_res&.texto ].compact.join(" | ").presence

      poliza = poliza_existente(cliente, numero_poliza, aseguradora)

      if poliza
        consolidar_poliza(poliza, hoja, fila, notas: notas, detalle_bien: detalle_bien,
                          observaciones: observaciones, forma_pago: forma_pago, cobertura: cobertura)
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
          observaciones: observaciones,
          estatus: estatus,
          motivo_cancelacion: motivo_cancelacion,
          notas: notas
        )
        reporte.contar(:polizas_creadas)

        if forma_pago.blank? && estatus == "vigente"
          flaggear(poliza, hoja, fila, "sin forma de pago legible; se asumió anual")
        end
        flaggear(poliza, hoja, fila, "aseguradora (CIA) no reconocida") if aseguradora_desconocida
        flaggear(poliza, hoja, fila, "broker/agente no reconocido") if broker_desconocido
      end

      if importe_res&.texto
        flaggear(poliza, hoja, fila, "importe ilegible (\"#{importe_res.texto}\"); se movió a notas")
      end

      if vencimiento.present? && fecha_res.nil?
        flaggear(poliza, hoja, fila, "fecha de vencimiento ilegible (\"#{L.texto_celda(vencimiento)}\")")
      end

      if fecha_res && estatus == "vigente"
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
    def consolidar_poliza(poliza, hoja, fila, notas:, detalle_bien:, forma_pago:, cobertura:, observaciones: nil)
      poliza.notas = [ poliza.notas, notas ].compact.join(" | ").presence if notas

      diferencias = []
      diferencias << "detalle_bien" if detalle_bien.present? && poliza.detalle_bien.present? && detalle_bien != poliza.detalle_bien
      diferencias << "forma_pago" if forma_pago.present? && poliza.forma_pago != forma_pago
      diferencias << "cobertura" if cobertura.present? && poliza.cobertura.present? && cobertura != poliza.cobertura

      poliza.detalle_bien ||= detalle_bien
      poliza.cobertura ||= cobertura
      if observaciones.present? && !poliza.observaciones.to_s.include?(observaciones)
        poliza.observaciones = [ poliza.observaciones, observaciones ].compact_blank.join(" | ")
      end
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
    def encontrar_poliza(numero, nombre, aseguradora: nil)
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
      return nil unless cliente

      # Preferir la póliza de la misma aseguradora que reporta la comisión.
      candidatas = cliente.polizas.order(:created_at)
      (aseguradora && candidatas.where(aseguradora: aseguradora).last) || candidatas.last
    end

    # Los pagos de la hoja de comisiones son históricos: se vinculan a un recibo
    # cercano (±45 días) sin comisión, o se crea el recibo pagado de ese periodo.
    def recibo_para_comision(poliza, fecha)
      if fecha
        cercano = poliza.recibos
                        .select { |r| r.comision.nil? && (r.fecha_vencimiento - fecha).abs <= 45 }
                        .min_by { |r| (r.fecha_vencimiento - fecha).abs }
        return cercano if cercano

        recibo = poliza.recibos.create!(fecha_vencimiento: fecha, estatus: "pagado", fecha_pago: fecha)
        reporte.contar(:recibos_creados)
        return recibo
      end

      sin_comision = poliza.recibos.detect { |r| r.comision.nil? }
      return sin_comision if sin_comision

      recibo = poliza.recibos.create!(fecha_vencimiento: Date.current, estatus: "pendiente")
      reporte.contar(:recibos_creados)
      recibo
    end

    def parsear_porcentaje(valor)
      res = L.parsear_importe(valor)
      return nil unless res&.importe

      pct = res.importe
      pct < 1 ? (pct * 100).round(2) : pct # 0.08 => 8%
    end

    def forma_por_periodo(desde, hasta)
      return nil unless desde && hasta

      dias = (hasta - desde).to_i
      case dias
      when 25..35 then "mensual"
      when 85..95 then "trimestral"
      when 175..190 then "semestral"
      when 360..370 then "anual"
      end
    end

    # ---- Utilidades de filas y headers ----
    def fila_vacia?(celdas)
      celdas.all? { |c| L.texto_celda(c).blank? }
    end

    HEADER_KEYWORDS = /\A(CLAVE|AGENTE|P[OÓ]LIZAS?|No\.? ?DE ?P[OÓ]LIZA|CONTRATANTE|ASEGURADO|NOMBRE|VENC|FECHA|IMPORTE|PRIMA|FORMA|F ?PAGO|F DE PAGO|RAMO|TIPO|PLAN|COBERTURA|CIA|C[IÍ]A|MONEDA|MOTIVO|DETALLE|VEH[IÍ]CULO|DESCRIPCI[OÓ]N|OBSERVACIONES|ESTATUS|MARCA|CARACT|COMUNICACI[OÓ]N|%|COMI)/i

    def fila_header?(celdas)
      textos = celdas.map { |c| L.texto_celda(c) }.compact
      return false if textos.size < 2

      coincidencias = textos.count { |t| t.match?(HEADER_KEYWORDS) }
      coincidencias >= [ textos.size / 2, 2 ].max
    end

    # Un bloque de la hoja de comisiones arranca con un header que trae
    # PÓLIZA y además PRIMA o COMISIÓN (hay tres formatos distintos apilados).
    def fila_header_comisiones?(celdas)
      textos = celdas.map { |c| L.texto_celda(c) }.compact.join(" ")
      textos.match?(/P[OÓ]LIZA/i) && textos.match?(/PRIMA|COMISI/i) && !textos.match?(/\A\d/)
    end

    COLUMNAS = {
      numero_poliza: /P[OÓ]LIZA/i,
      contratante: /CONTRATANTE|ASEGURADO|NOMBRE/i,
      fecha_pago: /FECHA DE PAGO/i,
      importe: /IMPORTE|PRIMA TOTAL|\APRIMA\z/i,
      prima_neta: /PRIMA ?NETA/i,
      recibo: /\ARECIBO\z/i,
      cia: /COMPAÑ[IÍ]A|ASEGURADORA|\AC[IÍ]A\.?\z/i,
      ramo: /\ARAMO\z/i,
      porcentaje: /%|PORC/i,
      comision: /\ACOMISI[OÓ]N\z|\ACOMI\z/i
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
