require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "la raíz saluda al usuario y muestra los contadores" do
    get root_path
    assert_response :success
    assert_match "Hola, Irma", response.body
    assert_match "Vencidos", response.body
    assert_match "Vencen esta semana", response.body
    assert_match "Vencen este mes", response.body
  end

  test "los contadores enlazan a vencimientos filtrados" do
    get root_path
    assert_match vencimientos_path(hasta: Date.yesterday), CGI.unescapeHTML(response.body)
  end
end
