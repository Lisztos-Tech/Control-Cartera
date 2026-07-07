# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_07_07_031819) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "unaccent"

  create_table "clientes", force: :cascade do |t|
    t.string "nombre", null: false
    t.string "telefono"
    t.string "email"
    t.text "notas"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nombre"], name: "index_clientes_on_nombre"
    t.index ["nombre"], name: "index_clientes_on_nombre_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "comisiones", force: :cascade do |t|
    t.bigint "recibo_id", null: false
    t.decimal "prima_neta", precision: 12, scale: 2
    t.decimal "porcentaje", precision: 5, scale: 2
    t.decimal "monto", precision: 12, scale: 2
    t.string "estatus", default: "por_cobrar", null: false
    t.date "fecha_cobro"
    t.text "notas"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["estatus"], name: "index_comisiones_on_estatus"
    t.index ["recibo_id"], name: "index_comisiones_on_recibo_id", unique: true
  end

  create_table "polizas", force: :cascade do |t|
    t.bigint "cliente_id", null: false
    t.string "numero_poliza"
    t.string "aseguradora", null: false
    t.string "canal", null: false
    t.string "broker"
    t.string "clave_agente"
    t.string "ramo", null: false
    t.string "cobertura"
    t.string "forma_pago", null: false
    t.decimal "prima_total", precision: 12, scale: 2
    t.string "moneda", default: "mxn", null: false
    t.string "detalle_bien"
    t.string "estatus", default: "vigente", null: false
    t.text "motivo_cancelacion"
    t.text "notas"
    t.boolean "necesita_revision", default: false, null: false
    t.text "motivo_revision"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cliente_id"], name: "index_polizas_on_cliente_id"
    t.index ["estatus"], name: "index_polizas_on_estatus"
    t.index ["necesita_revision"], name: "index_polizas_on_necesita_revision"
    t.index ["numero_poliza"], name: "index_polizas_on_numero_poliza"
  end

  create_table "recibos", force: :cascade do |t|
    t.bigint "poliza_id", null: false
    t.string "numero_recibo"
    t.date "fecha_vencimiento", null: false
    t.decimal "importe", precision: 12, scale: 2
    t.date "fecha_pago"
    t.string "estatus", default: "pendiente", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["estatus"], name: "index_recibos_on_estatus"
    t.index ["fecha_vencimiento"], name: "index_recibos_on_fecha_vencimiento"
    t.index ["poliza_id"], name: "index_recibos_on_poliza_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "comisiones", "recibos"
  add_foreign_key "polizas", "clientes"
  add_foreign_key "recibos", "polizas"
  add_foreign_key "sessions", "users"
end
