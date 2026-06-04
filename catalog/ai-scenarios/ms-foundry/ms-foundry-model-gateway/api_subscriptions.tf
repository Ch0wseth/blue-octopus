resource "azurerm_api_management_subscription" "ms_foundry_azure_ai" {
  api_management_name = azurerm_api_management.this.name
  resource_group_name = local.resource_group_name
  api_id              = azurerm_api_management_api.ms_foundry_azure_ai.id
  display_name        = format("%s-ai-gateway", azapi_resource.ms_foundry_project.name)
  state               = "active"
  allow_tracing       = false

  depends_on = [
    azurerm_api_management_api_policy.ms_foundry_azure_ai,
  ]
}

# Built-in all-access subscription (used by Agent Service via ai-gateway connection)
data "azapi_resource_action" "apim_builtin_subscription_keys" {
  type        = "Microsoft.ApiManagement/service/subscriptions@2024-05-01"
  resource_id = "${azurerm_api_management.this.id}/subscriptions/master"
  action      = "listSecrets"
  method      = "POST"

  response_export_values = ["primaryKey"]
}
