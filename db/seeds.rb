# Cuenta única de la app. En producción define ADMIN_EMAIL / ADMIN_PASSWORD
# la primera vez; después cámbiala por consola si hace falta.
User.find_or_create_by!(email_address: ENV.fetch("ADMIN_EMAIL", "irma@example.com")) do |user|
  user.password = ENV.fetch("ADMIN_PASSWORD", "cambiame123")
end

# Datos sintéticos de desarrollo: 10 clientes, ~20 pólizas, recibos variados.
# Idempotente: no duplica si ya corrió.

if Cliente.exists?
  puts "Ya hay datos; seeds omitidos."
  return
end

NOMBRES = [
  "JUAN PEREZ LOPEZ", "MARIA GARCIA HERNANDEZ", "PEDRO SANCHEZ RUIZ",
  "LAURA MARTINEZ DIAZ", "CARLOS RODRIGUEZ VEGA", "ANA TORRES MENDOZA",
  "TRANSPORTES DEL SUR SA DE CV", "JOSE RAMIREZ CASTRO",
  "SOFIA NAVARRO LUNA", "COMERCIALIZADORA JACARANDAS SA"
].freeze

VEHICULOS = [
  "FORD RANGER 2012", "NISSAN VERSA 2020", "VW JETTA 2018", "TOYOTA HILUX 2021",
  "HONDA CB500 2019", "FREIGHTLINER CASCADIA 2017", "HABITT JACARANDAS",
  "CHEVROLET AVEO 2022", "KIA RIO 2023", "LOCAL COMERCIAL CENTRO"
].freeze

srand(42)

clientes = NOMBRES.map.with_index do |nombre, i|
  Cliente.create!(
    nombre: nombre,
    telefono: "777#{1_000_000 + i * 111_111}",
    email: i.even? ? "cliente#{i}@example.com" : nil,
    notas: i == 3 ? "Prefiere que le llamen por la tarde" : nil
  )
end

combinaciones = [
  { aseguradora: "inbursa", canal: "directo", clave_agente: "10202" },
  { aseguradora: "inbursa", canal: "directo", clave_agente: "92491" },
  { aseguradora: "qualitas", canal: "directo" },
  { aseguradora: "qualitas", canal: "broker", broker: "cano" },
  { aseguradora: "ana_seguros", canal: "broker", broker: "cano" },
  { aseguradora: "seguros_atlas", canal: "broker", broker: "carmona" }
]

ramos_forma = [
  %w[autos mensual], %w[autos anual], %w[moto semestral], %w[camion trimestral],
  %w[vida anual], %w[gmm anual], %w[danos anual], %w[comercio semestral]
]

20.times do |i|
  cliente = clientes[i % clientes.size]
  combo = combinaciones[i % combinaciones.size]
  ramo, forma = ramos_forma[i % ramos_forma.size]

  poliza = cliente.polizas.create!(
    numero_poliza: "#{100_000 + i * 3_517}",
    aseguradora: combo[:aseguradora],
    canal: combo[:canal],
    broker: combo[:broker],
    clave_agente: combo[:clave_agente],
    ramo: ramo,
    cobertura: %w[AMPLIA LIMITADA].sample,
    forma_pago: forma,
    prima_total: rand(3_000..45_000),
    moneda: ramo == "vida" && i.odd? ? "usd" : "mxn",
    detalle_bien: VEHICULOS[i % VEHICULOS.size],
    estatus: "vigente",
    necesita_revision: i == 7,
    motivo_revision: i == 7 ? "importe ilegible en el Excel original" : nil
  )

  # Historial: un recibo pagado y uno o dos pendientes con fechas variadas
  # (algunos vencidos, algunos esta semana, algunos lejanos).
  meses = Poliza::PERIODOS_MESES.fetch(forma, 12)
  base = Date.current + rand(-40..60)

  poliza.recibos.create!(
    numero_recibo: "1/12",
    fecha_vencimiento: base - meses.months,
    importe: (poliza.prima_total / (12.0 / meses)).round(2),
    fecha_pago: base - meses.months + 2,
    estatus: "pagado"
  )
  recibo_pendiente = poliza.recibos.create!(
    numero_recibo: "2/12",
    fecha_vencimiento: base,
    importe: (poliza.prima_total / (12.0 / meses)).round(2),
    estatus: "pendiente"
  )

  # Comisiones para el canal broker (y una de vida Inbursa)
  if poliza.canal == "broker" || (poliza.ramo == "vida" && i.even?)
    Comision.create!(
      recibo: poliza.recibos.first,
      prima_neta: (poliza.prima_total * 0.85).round(2),
      porcentaje: [ 8, 10 ].sample,
      estatus: i.even? ? "por_cobrar" : "pagada",
      fecha_cobro: i.even? ? nil : Date.current - rand(10..90)
    )
  end
end

# Pólizas históricas no vigentes
[
  [ "cancelada", "cancelada por falta de pago" ],
  [ "no_renovada", "no se renovó, cliente cambió de aseguradora" ],
  [ "perdida_total", "PT POR ROBO" ]
].each_with_index do |(estatus, motivo), i|
  clientes[i].polizas.create!(
    numero_poliza: "HIST-#{i + 1}",
    aseguradora: "qualitas",
    canal: "directo",
    ramo: "autos",
    forma_pago: "anual",
    prima_total: rand(5_000..15_000),
    detalle_bien: VEHICULOS[i],
    estatus: estatus,
    motivo_cancelacion: motivo
  )
end

puts "Seeds: #{Cliente.count} clientes, #{Poliza.count} pólizas, #{Recibo.count} recibos, #{Comision.count} comisiones."
