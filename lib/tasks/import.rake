namespace :import do
  desc "Importa el Excel de Irma. Uso: rails import:excel[ruta/COMISIONES-IRMA.xlsx]. LIMPIAR=1 borra los datos antes (destroy + reimport)."
  task :excel, [ :path ] => :environment do |_t, args|
    path = args[:path]
    abort "Uso: rails import:excel[ruta/al/archivo.xlsx]" if path.blank?
    abort "No existe el archivo: #{path}" unless File.exist?(path)

    if ENV["LIMPIAR"] == "1"
      require Rails.root.join("lib/importador/reset")
      puts "Borrando datos existentes (LIMPIAR=1)..."
      Importador::Reset.limpiar!
    elsif Poliza.any?
      abort "La base ya tiene datos. Corre con LIMPIAR=1 para borrar y reimportar (el importador no es incremental)."
    end

    require Rails.root.join("lib/importador/excel")

    reporte = Importador::Excel.new(path).importar!
    reporte.imprimir
  end
end
