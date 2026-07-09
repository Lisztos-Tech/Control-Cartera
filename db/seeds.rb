require Rails.root.join("lib/seed_loader")

# Cuenta única de la app. En producción define ADMIN_EMAIL / ADMIN_PASSWORD
# la primera vez; después cámbiala por consola si hace falta.
User.find_or_create_by!(email_address: ENV.fetch("ADMIN_EMAIL", "irma@example.com")) do |user|
  user.password = ENV.fetch("ADMIN_PASSWORD", "cambiame123")
  user.nombre = ENV.fetch("ADMIN_NOMBRE", "Irma")
  user.apellido = ENV["ADMIN_APELLIDO"]
end

if SeedLoader.load!(reset: ENV["LIMPIAR"] == "1")
  puts "Seeds: #{Cliente.count} clientes, #{Poliza.count} pólizas, #{Recibo.count} recibos, #{Comision.count} comisiones."
end
