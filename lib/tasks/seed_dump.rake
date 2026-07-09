namespace :seed do
  desc "Exporta la BD actual a db/seeds/data/*.yml (para regenerar seeds desde datos importados)"
  task dump: :environment do
    require Rails.root.join("lib/seed_exporter")
    SeedExporter.dump!
  end
end
