require "pagy/extras/overflow"

Pagy::DEFAULT[:limit] = 25
Pagy::DEFAULT[:page_param] = :pagina
# Página fuera de rango (p.ej. filtro que reduce resultados): ir a la última.
Pagy::DEFAULT[:overflow] = :last_page
Pagy::DEFAULT.freeze
