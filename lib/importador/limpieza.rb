# Funciones puras de limpieza de datos del Excel fuente.
# Cada regla implementa exactamente lo documentado en el plan de importación.
module Importador
  module Limpieza
    FechaResultado = Struct.new(:fecha, :ambigua, keyword_init: true)
    ImporteResultado = Struct.new(:importe, :texto, keyword_init: true)
    NombreResultado = Struct.new(:nombre, :notas, keyword_init: true)

    EPOCH_EXCEL = Date.new(1899, 12, 30)
    # Rango plausible de seriales Excel: 2000-01-01 (36526) a 2060 aprox (58500).
    RANGO_SERIAL = 36_000..60_000

    RAMOS = {
      /MOTO/i => "moto",
      /CAMION|CAMIÓN|TRACTO/i => "camion",
      /AUTO|PICK ?UP|CARRO/i => "autos",
      /VIDA/i => "vida",
      /GMM|GASTOS ?M|MEDICO|MÉDICO|CANCER|CÁNCER/i => "gmm",
      /DAÑO|DANO|CASA|HOGAR|INMUEBLE|HABITT?/i => "danos",
      /\bRC\b|RESPONSABILIDAD/i => "rc",
      /COMERCIO|NEGOCIO|EMPRESA/i => "comercio"
    }.freeze

    # El Excel real trae "1.MEN", "2.TRI", "3.SEM", "4.AN" además de las
    # palabras completas.
    FORMAS_PAGO = {
      /MEN|1\/12/i => "mensual",
      /TRI/i => "trimestral",
      /SEM/i => "semestral",
      /ANUAL|AÑO|\.AN\b|\bAN\b/i => "anual",
      /CONTADO|UNICA|ÚNICA/i => "contado"
    }.freeze

    module_function

    # Regla 1: fechas en datetime nativo, serial numérico o string dd/mm/yyyy | m/d/yyyy.
    # Devuelve FechaResultado o nil si no es interpretable como fecha.
    def parsear_fecha(valor)
      case valor
      when Date, DateTime, Time
        FechaResultado.new(fecha: valor.to_date, ambigua: false)
      when Numeric
        return nil unless RANGO_SERIAL.cover?(valor.to_i)

        FechaResultado.new(fecha: EPOCH_EXCEL + valor.to_i, ambigua: false)
      when String
        parsear_fecha_string(valor)
      end
    end

    def parsear_fecha_string(texto)
      s = texto.strip.gsub(%r{/{2,}}, "/") # tolera typos "7/02//2024"
      return nil if s.empty?

      if s.match?(/\A\d{5}\z/) && RANGO_SERIAL.cover?(s.to_i)
        return FechaResultado.new(fecha: EPOCH_EXCEL + s.to_i, ambigua: false)
      end

      m = s.match(%r{\A(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\z})
      return nil unless m

      a, b, anio = m[1].to_i, m[2].to_i, m[3].to_i
      anio += 2000 if anio < 100

      dia, mes, ambigua =
        if a > 12 && b <= 12
          [ a, b, false ] # solo puede ser dd/mm
        elsif b > 12 && a <= 12
          [ b, a, false ] # formato US m/d
        elsif a == b
          [ a, b, false ] # 5/5: da igual
        else
          [ a, b, true ] # ambiguo: asumir dd/mm (MX) y flaggear
        end

      fecha = Date.new(anio, mes, dia) rescue nil
      return nil unless fecha

      FechaResultado.new(fecha: fecha, ambigua: ambigua)
    end

    # Regla 2: importes numéricos, "$4,921.50", "4295,07", "$ 3.856,12",
    # o basura tipo "PAGADA" (importe nil + texto para notas).
    def parsear_importe(valor)
      case valor
      when Numeric
        ImporteResultado.new(importe: BigDecimal(valor.to_s), texto: nil)
      when String
        parsear_importe_string(valor)
      end
    end

    def parsear_importe_string(texto)
      s = texto.strip
      return nil if s.empty?

      limpio = s.gsub(/[$\s]/, "")
      unless limpio.match?(/\A-?[\d.,]+\z/) && limpio.match?(/\d/)
        return ImporteResultado.new(importe: nil, texto: s)
      end

      ImporteResultado.new(importe: BigDecimal(normalizar_separadores(limpio)), texto: nil)
    rescue ArgumentError
      ImporteResultado.new(importe: nil, texto: s)
    end

    def normalizar_separadores(s)
      tiene_punto = s.include?(".")
      tiene_coma = s.include?(",")

      if tiene_punto && tiene_coma
        # El separador más a la derecha es el decimal; el otro es de miles.
        if s.rindex(".") > s.rindex(",")
          s.delete(",")
        else
          s.delete(".").tr(",", ".")
        end
      elsif tiene_coma
        # ",07" al final = coma decimal europea; si no, separador de miles.
        s.match?(/,\d{1,2}\z/) ? s.tr(",", ".") : s.delete(",")
      elsif tiene_punto
        # ".856" con tres dígitos al final = punto de miles.
        s.match?(/\.\d{3}\z/) ? s.delete(".") : s
      else
        s
      end
    end

    # Frases de estatus que la usuaria pega EN MAYÚSCULAS al final del nombre;
    # se cortan del nombre y se van a notas.
    FRASES_ESTADO = Regexp.union(
      /\b(SE CANCEL[OÓ]|C ?ANCELAD[OA]|CANCELACION)/,
      /\bPENDIENTE\b/,
      /\bNO ?SE PAG[OÓ]|\bNO (LA )?PAG[OÓ]\b|\bDEJ[OÓ] DE PAGAR/,
      /\bNO RENOVAR|\bS?E RENOV[OÓ]/,
      /\bVENDID[OA]|\bVENTA DEL?\b/,
      /\bPOR COBRAR|\bCHECAR|\bPAGAD[OA]\b|\bPAGO \d/,
      /\bSE (HIZO A|REEXPIDI[OÓ]|CAMBI[OÓ]|PAS[OÓ]|PAGO ?A)\b/,
      /\bPOL(IZA)? DUPLICADA|\bPERDIDA TOT|\bCLIENTE\b/
    )

    # Regla 3: el nombre es el prefijo en MAYÚSCULAS; la cola en minúsculas
    # ("esta poiza la pagué yo", "2/2", "cancelada") se va a notas, igual que
    # las frases de estatus en mayúsculas.
    def separar_nombre(texto)
      # [[:space:]] incluye el espacio no separable (U+00A0) que abunda en el Excel.
      s = texto.to_s.gsub(/[[:space:]]+/, " ").strip
      return NombreResultado.new(nombre: nil, notas: nil) if s.empty?

      tokens = s.split(" ")
      corte = tokens.index { |t| !token_de_nombre?(t) } || tokens.length

      nombre = tokens[0...corte].join(" ")
      notas = tokens[corte..].join(" ").presence

      if (m = nombre.match(FRASES_ESTADO))
        notas = [ nombre[m.begin(0)..].strip, notas ].compact.join(" | ").presence
        nombre = nombre[0...m.begin(0)]
      end

      # Conectores colgantes al final del nombre ("...GONZALEZ NO" cuando el
      # resto de la frase iba en minúsculas y ya se fue a notas).
      nombre = nombre.strip.sub(/(\s+(NO|SE|YA|LA|EL|DEL?))+\z/, "")

      NombreResultado.new(nombre: nombre.presence, notas: notas)
    end

    def token_de_nombre?(token)
      # Mayúsculas puras y sin dígitos ("2DE", "2/2" son anotaciones, no nombre)
      token.match?(/\p{Lu}/) && !token.match?(/\p{Ll}/) && !token.match?(/\d/)
    end

    def mapear_ramo(texto)
      s = texto.to_s.strip
      return nil if s.empty?

      RAMOS.each { |regex, ramo| return ramo if s.match?(regex) }
      "otro"
    end

    def mapear_forma_pago(texto)
      s = texto.to_s.strip
      return nil if s.empty?

      FORMAS_PAGO.each { |regex, forma| return forma if s.match?(regex) }
      nil
    end

    def mapear_moneda(texto)
      case texto.to_s.strip
      when /DOLAR|DÓLAR|DLLS|USD/i then "usd"
      when /NACIONAL|MXN|PESOS?/i then "mxn"
      else "mxn"
      end
    end

    # POL CANCELADAS: derivar estatus del texto del motivo.
    def mapear_estatus_cancelacion(texto)
      case texto.to_s
      when /PERDIDA ?TOT|PÉRDIDA ?TOT|\bPT\b/i then "perdida_total"
      when /NO SE RENOV|NO RENOV/i then "no_renovada"
      else "cancelada"
      end
    end

    def texto_celda(valor)
      case valor
      when nil then nil
      when Float then (valor % 1).zero? ? valor.to_i.to_s : valor.to_s
      else valor.to_s.strip.presence
      end
    end
  end
end
