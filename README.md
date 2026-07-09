# Control Cartera

Sistema de gestión de pólizas de seguros para agente independiente. Reemplaza el
archivo `COMISIONES-IRMA.xlsx`: vencimientos, recibos, comisiones y clientes en
una sola app.

- **Stack:** Rails 8 · PostgreSQL · Hotwire (Turbo + Stimulus) · Tailwind CSS · Solid Queue/Cache
- **Usuaria única**, UI en español (México), desktop-first, self-hosted.

## Desarrollo

Requisitos: Docker y Docker Compose.

```bash
docker compose up
```

Levanta Postgres 17 y la app en `http://localhost:3000`. En el primer arranque
`db:seed` carga los datos reales desde `db/seeds/data/*.yml`.
La cuenta de desarrollo es `irma@example.com` / `cambiame123`.

Sin Docker (Ruby 3.4+ y un Postgres local en el puerto 5433):

```bash
bundle install
bin/rails db:prepare db:seed
bin/dev
```

### Tests

```bash
bin/rails test            # modelos, importador y controladores
bin/rails test:system     # los 3 flujos críticos (Chrome headless)
```

## Datos iniciales (seeds)

`bin/rails db:seed` crea la cuenta de admin y carga clientes, pólizas, recibos y
comisiones desde `db/seeds/data/*.yml` (snapshot de la migración del Excel).
Es idempotente: si ya hay pólizas, no vuelve a cargar.

```bash
bin/rails db:seed

# Borrar clientes/pólizas/recibos/comisiones y volver a cargar:
LIMPIAR=1 bin/rails db:seed
```

Para regenerar los YAML desde una BD ya importada:

```bash
bin/rails seed:dump
```

Importación manual del Excel (solo si necesitas refrescar desde el archivo):

```bash
bin/rails "import:excel[/ruta/a/COMISIONES-IRMA.xlsx]"
LIMPIAR=1 bin/rails "import:excel[/ruta/a/COMISIONES-IRMA.xlsx]"
bin/rails seed:dump   # luego actualiza db/seeds/data/
```

El importador:

- Lee las hojas primarias (`VENCIMIENTOS INBURSA`, `VENC QUALITAS`, `VENC QS BROKER`,
  `POLIZAS VIDA`, `POL CANCELADAS`, `FORM PAGO COMI QS`).
- Normaliza fechas (datetime, serial de Excel, strings `dd/mm/yyyy` y `m/d/yyyy`),
  importes (`$4,921.50`, `4295,07`, `$ 3.856,12`) y nombres contaminados.
- Consolida filas duplicadas de renovación en una póliza con N recibos.
- Deduplica clientes por similitud; los pares dudosos NO se fusionan, se reportan.
- Flaggea todo registro dudoso con `necesita_revision` + motivo legible
  (visible en la app en "Necesitan revisión").
- Usa `Hoja1/Hoja3/Hoja4` solo para reconciliar y reportar pólizas faltantes.
- Imprime al final el resumen: creados, flaggeados, ignorados y por qué.

## Deploy (producción)

La imagen de producción es el `Dockerfile` estándar de Rails 8 (multi-stage,
assets precompilados). El contenedor corre detrás del Nginx existente del host;
Postgres es el del servidor (no va en contenedor).

### 1. Variables de entorno

| Variable | Descripción |
|---|---|
| `DATABASE_URL` | `postgres://usuario:password@host:5432/control_cartera` (Postgres existente del servidor). La app, Solid Queue y Solid Cache usan esta misma base. |
| `RAILS_MASTER_KEY` | Contenido de `config/master.key` |
| `SECRET_KEY_BASE` | Generar con `bin/rails secret` |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | Credenciales de la cuenta única (solo las usa `db:seed` la primera vez) |

La base de datos necesita las extensiones `pg_trgm` y `unaccent`
(las migraciones las habilitan; el usuario de Postgres debe poder crearlas, o
créalas antes con un superusuario: `CREATE EXTENSION pg_trgm; CREATE EXTENSION unaccent;`).

### 2. Build y arranque

```bash
docker build -t control-cartera .

docker run -d --name control-cartera \
  --restart unless-stopped \
  -p 127.0.0.1:8300:80 \
  -e DATABASE_URL="postgres://usuario:password@172.17.0.1:5432/control_cartera" \
  -e RAILS_MASTER_KEY="..." \
  -e SECRET_KEY_BASE="..." \
  control-cartera

# Primera vez: crear el esquema y la cuenta
docker exec -e ADMIN_EMAIL=irma@ejemplo.com -e ADMIN_PASSWORD=segura \
  control-cartera bin/rails db:prepare db:seed
```

El healthcheck es `GET /up` (incluido en Rails 8).

### 3. Server block de Nginx (reverse proxy + TLS ya existentes en el host)

```nginx
server {
    listen 443 ssl;
    server_name polizas.ejemplo.com;

    # ssl_certificate / ssl_certificate_key según la config existente del host

    location / {
        proxy_pass http://127.0.0.1:8300;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Con `config.assume_ssl`/`config.force_ssl` activos (default de producción),
Nginx debe mandar `X-Forwarded-Proto`.

### 4. Backups

Cron diario de `pg_dump` en el host (ajustar usuario/base):

```cron
# /etc/cron.d/backup-control-cartera
0 3 * * * postgres pg_dump -Fc control_cartera > /var/backups/control-cartera/$(date +\%F).dump && find /var/backups/control-cartera -name "*.dump" -mtime +30 -delete
```

Restaurar: `pg_restore -d control_cartera --clean archivo.dump`.

### 5. Cambiar la contraseña

```bash
docker exec -it control-cartera bin/rails runner 'User.first.update!(password: "nueva")'
```

No hay registro público, ni roles, ni reset por email.

## Estructura relevante

```
app/models/               Cliente, Poliza, Recibo, Comision, FiltroRecibos
lib/importador/           limpieza.rb (reglas puras), excel.rb (orquestación), reporte.rb
lib/tasks/import.rake     rails import:excel[path]
test/support/fixture_excel.rb  genera el .xlsx de prueba con casos patológicos
```

## Decisiones de diseño

- **"Vencido" no se persiste:** un recibo vencido es un pendiente con fecha
  pasada (scope `Recibo.vencidos`); no hay estado que se desactualice solo.
- **Sin borrado físico** de pólizas ni clientes desde la UI; solo cambio de
  estatus. Los recibos sí se pueden borrar (errores de captura).
- **El siguiente recibo se propone, no se crea solo:** al marcar pagado un
  recibo de póliza periódica la app ofrece crearlo con un clic (los importes
  cambian en renovaciones anuales).
- El número de póliza **no es único**: hay pólizas sin número y renovaciones
  que lo reutilizan. Los posibles duplicados se avisan en la UI, sin bloquear.
