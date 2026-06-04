resource "azurerm_api_management_api_policy" "ms_foundry_azure_ai" {
  api_name            = azurerm_api_management_api.ms_foundry_azure_ai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = local.resource_group_name

  xml_content = data.template_file.inference_api_global_policy.rendered

  depends_on = [
    azurerm_role_assignment.apim_ms_foundry_openai_user,
  ]
}

resource "azurerm_api_management_api_operation_policy" "ms_foundry_azure_ai_deployments" {
  api_name            = azurerm_api_management_api.ms_foundry_azure_ai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = local.resource_group_name
  operation_id        = "getChatCompletionsWithDeployment"

  xml_content = data.template_file.inference_api_deployments_policy.rendered

  depends_on = [
    azurerm_api_management_api_policy.ms_foundry_azure_ai,
    azurerm_api_management_backend.ms_foundry_azure_ai_openai,
  ]
}
