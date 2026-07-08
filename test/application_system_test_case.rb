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
end
