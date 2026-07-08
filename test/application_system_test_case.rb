require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    # GitHub Actions runners need these flags for stable headless Chrome.
    if ENV["CI"]
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")
    end
  end

  def iniciar_sesion(user = users(:irma))
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "password"
    click_button "Entrar"
    assert_text "Vencimientos"
  end

  # Headless Chrome on CI can miss Stimulus debounce handlers; set value and submit in-page.
  def buscar_vencimientos(termino)
    page.execute_script(<<~JS, termino)
      const input = document.querySelector("input[name='q']");
      input.value = arguments[0];
      input.closest("form").requestSubmit();
    JS
  end

  def filtrar_aseguradora(valor)
    page.execute_script(<<~JS, valor)
      const select = document.querySelector("select[name='aseguradora']");
      select.value = arguments[0];
      select.dispatchEvent(new Event("change", { bubbles: true }));
      select.closest("form").requestSubmit();
    JS
  end

  def enviar_formulario_principal
    page.execute_script(<<~JS)
      const form = document.querySelector("main form");
      if (form) form.requestSubmit();
    JS
  end
end
