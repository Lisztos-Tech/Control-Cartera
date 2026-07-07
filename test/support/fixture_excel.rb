require "caxlsx"

# Construye un .xlsx reducido con los casos patológicos documentados en el plan:
# fecha serial, fecha string US, typo de doble slash, importe con coma decimal,
# basura en columna de importe, nombre contaminado, póliza duplicada (renovación),
# sección TARJETAS VRIM, par de clientes dudoso y hoja secundaria para reconciliar.
module FixtureExcel
  module_function

  def construir(path)
    paquete = Axlsx::Package.new
    libro = paquete.workbook

    libro.add_worksheet(name: "VENCIMIENTOS INBURSA") do |hoja|
      hoja.add_row [ "CLAVE", "POLIZA", "CONTRATANTE", "VENCIMIENTO", "IMPORTE", "FORMA PAGO", "TIPO", "PLAN" ]
      # Fila normal con fecha nativa
      hoja.add_row [ "10202", "111111", "JUAN PEREZ LOPEZ", Date.new(2026, 8, 15), 4921.50, "MENSUAL", "AUTOS", "AMPLIA" ]
      # Renovación duplicada: misma póliza, otro vencimiento (debe consolidar recibos)
      hoja.add_row [ "10202", "111111", "JUAN PEREZ LOPEZ", Date.new(2026, 9, 15), 4921.50, "MENSUAL", "AUTOS", "AMPLIA" ]
      # Fecha serial de Excel (46077 = 2026-02-25) y nombre contaminado con 20 espacios
      hoja.add_row [ "10206", "222222", "MARIA GARCIA HERNANDEZ                    esta poiza la pagué yo", 46077, "$4,921.50", "ANUAL", "VIDA", nil ]
      # Importe basura -> notas + flag
      hoja.add_row [ "10207", "333333", "PEDRO SANCHEZ RUIZ", Date.new(2026, 7, 20), "PAGADA", "SEMESTRAL", "MOTO", "LIMITADA" ]
      # Par dudoso de clientes (vs ANDERSON BREWSTER en QUALITAS)
      hoja.add_row [ "92491", "444444", "ANDERSON WEBSTER", Date.new(2026, 10, 1), 3000, "ANUAL", "AUTOS", "AMPLIA" ]
      # Fila sin contratante -> ignorada
      hoja.add_row [ "10213", "555555", nil, Date.new(2026, 7, 1), 1000, "MENSUAL", "AUTOS", nil ]
      # Sección VRIM al pie
      hoja.add_row [ nil, nil, "TARJETAS VRIM", nil, nil, nil, nil, nil ]
      hoja.add_row [ nil, nil, "LUIS LARA", nil, nil, nil, nil, nil ]
      hoja.add_row [ nil, nil, "ROSA MELANO", nil, nil, nil, nil, nil ]
    end

    libro.add_worksheet(name: "VENC QUALITAS") do |hoja|
      hoja.add_row [ "CLAVE", "POLIZA", "CONTRATANTE", "VENCIMIENTO", "IMPORTE", "FORMA PAGO", "TIPO", "PLAN" ]
      hoja.add_row [ nil, "Q-1001", "ANDERSON BREWSTER", Date.new(2026, 8, 1), 5500, "ANUAL", "AUTOS", "AMPLIA" ]
      # Importe con coma decimal europea
      hoja.add_row [ nil, "Q-1002", "CARLA MONTES DE OCA", Date.new(2026, 9, 10), "4295,07", "TRIMESTRAL", "CAMION", "RC BASICO" ]
    end

    libro.add_worksheet(name: "VENC QS BROKER") do |hoja|
      hoja.add_row [ "CIA", "AGENTE", "POLIZA", "CONTRATANTE", "VENCIMIENTO", "IMPORTE", "FORMA PAGO", "TIPO" ]
      hoja.add_row [ "ANA SEGUROS", "CANO", "AN-77", "RAUL JIMENEZ ROJO", Date.new(2026, 7, 25), 2500, "ANUAL", "AUTOS" ]
      hoja.add_row [ "SEGUROS ATLAS", "CARMONA", "AT-88", "SOFIA NAVARRO", Date.new(2026, 8, 5), "$ 3.856,12", "SEMESTRAL", "COMERCIO" ]
      # CIA no reconocida -> flag
      hoja.add_row [ "GNP", "CANO", "GN-99", "HUGO SS", Date.new(2026, 9, 1), 1200, "ANUAL", "AUTOS" ]
    end

    libro.add_worksheet(name: "POLIZAS VIDA") do |hoja|
      hoja.add_row [ "CLAVE", "POLIZA", "CONTRATANTE", "VENCIMIENTO", "IMPORTE", "FORMA PAGO", "MONEDA" ]
      # TODO viene como string, incluida la fecha dd/mm/yyyy y el importe
      hoja.add_row [ "92498", "VI-501", "TERESA VALDES", "13/09/2026", "1500.00", "ANUAL", "DOLARES" ]
      hoja.add_row [ "92498", "VI-502", "OMAR BRAVO", "01/12/2026", "12,000.00", "ANUAL", "NACIONAL" ]
    end

    libro.add_worksheet(name: "POL CANCELADAS") do |hoja|
      hoja.add_row [ "POLIZA", "CONTRATANTE", "TIPO", "MOTIVO" ]
      hoja.add_row [ "C-100", "IGNACIO SOLARES", "AUTOS", "no se renovó" ]
      hoja.add_row [ "C-200", "BERTA OLIVA", "AUTOS", "PT POR ROBO" ]
      hoja.add_row [ "C-300", "DARIO FUENTES", "MOTO", "cancelada por falta de pago" ]
    end

    libro.add_worksheet(name: "FORM PAGO COMI QS") do |hoja|
      # Bloque 1
      hoja.add_row [ "FECHA ENVÍO REPORTE", "No. DE PÓLIZA", "ASEGURADO", "PRIMA NETA", "%", "COMISIÓN" ]
      # Fecha string US (12/15/2023: día>12 en segunda posición, sin ambigüedad)
      hoja.add_row [ "12/15/2023", "Q-1001", "ANDERSON BREWSTER", "4295,07", 0.10, nil ]
      # Fila que no vincula a ninguna póliza
      hoja.add_row [ "10/01/2024", "ZZ-404", "NADIE CONOCIDO", 100, 0.08, 8 ]
      hoja.add_row []
      # Bloque 2 (header repetido)
      hoja.add_row [ "FECHA ENVÍO REPORTE", "No. DE PÓLIZA", "ASEGURADO", "PRIMA NETA", "%", "COMISIÓN" ]
      # Typo doble slash + fecha ambigua (7/02 => flag)
      hoja.add_row [ "7/02//2024", "AN-77", "RAUL JIMENEZ ROJO", "$ 3.856,12", "8", nil ]
    end

    libro.add_worksheet(name: "Hoja1") do |hoja|
      hoja.add_row [ "POLIZA", "CONTRATANTE" ]
      hoja.add_row [ "111111", "JUAN PEREZ LOPEZ" ]     # ya existe: no reportar
      hoja.add_row [ "HUERFANA-9999", "ALGUIEN OLVIDADO" ] # no existe: reportar
    end

    paquete.serialize(path)
    path
  end
end
