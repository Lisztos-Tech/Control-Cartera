require "caxlsx"

# Construye un .xlsx reducido que replica los layouts REALES de COMISIONES-IRMA.xlsx
# con los casos patológicos documentados en el plan: fecha serial, fecha string US,
# typo de doble slash, importe con coma decimal, basura en columna de importe,
# nombre contaminado, póliza duplicada (renovación), sección TARJETAS VRIM,
# par de clientes dudoso y hoja secundaria para reconciliar.
module FixtureExcel
  module_function

  def construir(path)
    paquete = Axlsx::Package.new
    libro = paquete.workbook

    # Layout real: A=clave, B=numero, C=contratante, D=venc, E=importe,
    # F=forma, G=ramo, H=plan, I=detalle, J=extra
    libro.add_worksheet(name: "VENCIMIENTOS INBURSA") do |hoja|
      hoja.add_row [ nil, nil, "Contratante", "Vencimiento", "Importe Recibo", "FORMA PAGO", "TIPO", "PLAN", "Observaciones", nil ]
      # Fila normal con fecha nativa
      hoja.add_row [ "10202", "111111", "JUAN PEREZ LOPEZ", Date.new(2026, 8, 15), 4921.50, "MENSUAL", "AUTOS", "AMPLIA", "FORD RANGER 2012", nil ]
      # Renovación duplicada: misma póliza, otro vencimiento (debe consolidar recibos)
      hoja.add_row [ "10202", "111111", "JUAN PEREZ LOPEZ", Date.new(2026, 9, 15), 4921.50, "MENSUAL", "AUTOS", "AMPLIA", "FORD RANGER 2012", nil ]
      # Fecha serial de Excel (46077 = 2026-02-24) y nombre contaminado con padding
      hoja.add_row [ "10206", "222222", "MARIA GARCIA HERNANDEZ                    esta poiza la pagué yo", 46077, "$4,921.50", "4.AN", "VIDA", nil, nil, nil ]
      # Importe basura -> notas + flag; forma abreviada real "3.SEM"
      hoja.add_row [ "10207", "333333", "PEDRO SANCHEZ RUIZ", Date.new(2026, 7, 20), "PAGADA", "3.SEM", "MOTO", "LIMITADA", nil, nil ]
      # Par dudoso de clientes (vs ANDERSON BREWSTER en QUALITAS)
      hoja.add_row [ "92491", "444444", "ANDERSON WEBSTER", Date.new(2026, 10, 1), 3000, "ANUAL", "AUTOS", "AMPLIA", nil, nil ]
      # Fila sin contratante -> ignorada
      hoja.add_row [ "10213", "555555", nil, Date.new(2026, 7, 1), 1000, "1.MEN", "AUTOS", nil, nil, nil ]
      # Sección VRIM al pie
      hoja.add_row [ nil, nil, "TARJETAS VRIM", nil, nil, nil, nil, nil, nil, nil ]
      hoja.add_row [ nil, nil, "LUIS LARA", nil, nil, nil, nil, nil, nil, nil ]
      hoja.add_row [ nil, nil, "ROSA MELANO Checar vencimiento", nil, nil, nil, nil, nil, nil, nil ]
    end

    # Layout real: A=numero, B=contratante, C=venc, D=importe, E=forma, F=ramo,
    # G=cia, H=?, I=marca/detalle, J=extra
    libro.add_worksheet(name: "VENC QUALITAS") do |hoja|
      hoja.add_row [ "POLIZA", "QUALITAS", "VENC", "PRIMA TOTAL", "F PAGO", nil, "COBERTURA", "ESTATUS", "MARCA", nil ]
      hoja.add_row [ "Q-1001", "ANDERSON BREWSTER", Date.new(2026, 8, 1), 5500, "ANUAL", "AUTOS", "QUALITAS", nil, "T CROSS", nil ]
      # Importe con coma decimal europea + contacto en columna extra
      hoja.add_row [ "Q-1002", "CARLA MONTES DE OCA", Date.new(2026, 9, 10), "4295,07", "TRIMESTRAL", "CAMION", "QUALITAS", nil, "FREIGHTLINER", "ANGELICA contacto@mail.com" ]
    end

    # Layout real: A=numero, B=asegurado, C=venc, D=importe, E=cia, F=forma,
    # G=cobertura, H=pago, I=caract/detalle, J=comunicación, K=agente
    libro.add_worksheet(name: "VENC QS BROKER") do |hoja|
      hoja.add_row [ nil, "ASEGURADO", "VENC", nil, "CIA", "F DE PAGO", "COBERTURA", "PAGO", "CARACT", "COMUNICACIÓN", "AGENTE", "A QUIEN HABLAR" ]
      hoja.add_row [ "AN-77", "RAUL JIMENEZ ROJO", Date.new(2026, 7, 25), 2500, "ANA SEGUROS", "ANUAL", "AMPLIA", nil, "NISSAN NP 300 2018", nil, "BROKER CANO", nil ]
      # Importe con punto de miles + coma decimal; broker carmona
      hoja.add_row [ "AT-88", "SOFIA NAVARRO", Date.new(2026, 8, 5), "$ 3.856,12", "SEGUROS ATLAS", "SEMESTRAL", "AMPLIA", nil, "LOCAL COMERCIO", nil, "CARMONA", nil ]
      # CIA no reconocida + agente no reconocido -> flags
      hoja.add_row [ "GN-99", "HUGO SS", Date.new(2026, 9, 1), 1200, "GNP", "ANUAL", "AMPLIA", nil, nil, nil, "PABLO SANCHEZ", nil ]
      # Sin numero, sin broker, nota en minúsculas dentro del nombre
      hoja.add_row [ nil, "ISIDRO RABADAN (cotizar en enero)", Date.new(2026, 10, 1), nil, nil, nil, nil, nil, nil, nil, nil, nil ]
    end

    # Layout real: reporte Inbursa, TODO en strings
    libro.add_worksheet(name: "POLIZAS VIDA") do |hoja|
      hoja.add_row [ "Emisor", "Carpeta", "Recibo", "Importe", "Moneda", "Tipo Cobro", "Asegurado", "Cliente", "Fecha Efecto", "Fecha Vencimiento", "Fecha Pago", "Comisión" ]
      # Mensual USD pagado con comisión
      hoja.add_row [ "92498", "VI-501", "94255407", "137.8", "DOLARES", "BANCARIO", "TERESA VALDES", "980673", "28/08/2026", "28/09/2026", "28/08/2026", "115.76" ]
      # Anual MXN sin pagar, sin comisión, importe con coma de miles
      hoja.add_row [ "92498", "VI-502", "94243536", "12,000.00", "NACIONAL", "BANCARIO", "OMAR BRAVO", "48921", "01/12/2025", "01/12/2026", nil, "0" ]
    end

    # Layout real: A=clave, B=numero, C=contratante, D=venc, E=importe,
    # F=forma("1.MEN"), G=ramo, H..=texto libre (estatus/motivo/detalle)
    libro.add_worksheet(name: "POL CANCELADAS") do |hoja|
      hoja.add_row [ nil, nil, "POLIZAS CANCELADAS", "Vencimiento", "Importe Recibo", "f pago", "RAMO", nil, "Observaciones", nil ]
      hoja.add_row [ "10202", "C-100", "IGNACIO SOLARES", Date.new(2024, 4, 1), 418.06, "1.MEN", nil, "cancelada", "no se renovó", nil ]
      hoja.add_row [ "10202", "C-200", "BERTA OLIVA", Date.new(2023, 9, 1), nil, "4.AN", nil, "cancelada", "PT POR ROBO", nil ]
      hoja.add_row [ "10202", "C-300", "DARIO FUENTES", Date.new(2024, 5, 9), 515.81, "1.MEN", nil, "cancelada", "cancelada por falta de pago", "QUALITAS" ]
    end

    # Layout real: bloques apilados con headers distintos
    libro.add_worksheet(name: "FORM PAGO COMI QS") do |hoja|
      # Bloque estilo 1 (viejo): POLIZA / ASEGURADO / VIGENCIA / COMPAÑÍA / AGENTE / SUBAGENTE / PRIMA / FECHA DE PAGO
      hoja.add_row [ "POLIZA", "ASEGURADO", "VIGENCIA", "COMPAÑÍA", "AGENTE", "SUBAGENTE", "PRIMA", "FECHA DE PAGO" ]
      # Fecha string US (12/15/2023: día>12, sin ambigüedad); vincula por número
      hoja.add_row [ "Q-1001", "ANDERSON BREWSTER", Date.new(2023, 11, 7), "QUALITAS", 3869, "MANUEL SM", "4295,07", "12/15/2023" ]
      # Fila que no vincula a ninguna póliza
      hoja.add_row [ "ZZ-404", "NADIE CONOCIDO", nil, "QUALITAS", nil, nil, 100, "10/01/2024" ]
      hoja.add_row []
      # Bloque estilo 2 (nuevo): FECHA ENVÍO REPORTE / No. DE PÓLIZA / ENDOSO / NOMBRE DEL CONTRATANTE / ...
      hoja.add_row [ "FECHA ENVÍO REPORTE", "No. DE PÓLIZA", "ENDOSO", "NOMBRE DEL CONTRATANTE", "ASEGURADORA", "RAMO", "PRIMA NETA", "PRIMA TOTAL", "FECHA DE PAGO", "RECIBO", "% DE COMI", "COMISION", "AGENTE" ]
      # Typo doble slash + fecha ambigua (7/02 => flag); porcentaje como fracción 0.1
      hoja.add_row [ Date.new(2024, 2, 10), "AN-77", 1, "RAUL JIMENEZ ROJO", "ANA SEGUROS", "AUTOS", "$ 3.856,12", 4500, "7/02//2024", "1/1", 0.1, nil, 3869 ]
      # Porcentaje corrupto "#DIV/0!" -> se ignora el porcentaje
      hoja.add_row [ Date.new(2024, 3, 1), "AT-88", nil, "SOFIA NAVARRO", "SEGUROS ATLAS", "COMERCIO", 2741.58, 3180.24, Date.new(2024, 3, 5), "2/2", "#DIV/0!", 274.16, nil ]
    end

    libro.add_worksheet(name: "Hoja1") do |hoja|
      hoja.add_row [ nil, "POLIZA", "CONTRATANTE" ]
      hoja.add_row [ nil, "111111", "JUAN PEREZ LOPEZ" ]      # ya existe: no reportar
      hoja.add_row [ nil, "99990001", "ALGUIEN OLVIDADO" ]    # no existe: reportar
      hoja.add_row [ nil, "99990002", "OTRO OLVIDADO" ]
      hoja.add_row [ nil, "99990003", "TERCERO OLVIDADO" ]
    end

    paquete.serialize(path)
    path
  end
end
