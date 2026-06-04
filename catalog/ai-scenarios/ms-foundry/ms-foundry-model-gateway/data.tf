data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "this" {
  count = var.resource_group_name != "" ? 1 : 0
  name  = var.resource_group_name
}

# data "template_file" "foundry_policy" {
#   template = file("${path.module}/assets/policies/foundry-policy.xml.tpl")
#   vars = {
#     foundry_backend_id = azurerm_api_management_backend.ms_foundry.name
#   }
# }

data "template_file" "inference_api" {
  template = file("${path.module}/assets/apis/inference-api.json")
}

data "template_file" "inference_api_global_policy" {
  template = file("${path.module}/assets/policies/inference-api-global-policy.xml.tpl")
  vars = {
    foundry_backend_name       = azurerm_api_management_backend.ms_foundry_azure_ai.name
    foundry_openai_backend_url = format("%s/openai", trimsuffix(azapi_resource.ms_foundry_all_models.output.properties.endpoints["Azure AI Model Inference API"], "/"))
    tenant-id                  = data.azurerm_client_config.current.tenant_id
    identity_dev_client_id     = azurerm_user_assigned_identity.this.client_id
    identity_com_client_id     = azurerm_user_assigned_identity.foundry_common_models.client_id
    tokens_per_minute_dev      = var.tokens_per_minute_dev
    tokens_per_minute_com      = var.tokens_per_minute_com
  }
}

data "template_file" "inference_api_deployments_policy" {
  template = file("${path.module}/assets/policies/inference-api-deployments-policy.xml.tpl")
  vars = {
    foundry_openai_backend_name = azurerm_api_management_backend.ms_foundry_azure_ai_openai.name
  }
}


data "azapi_resource" "apim_service" {
  type        = "Microsoft.ApiManagement/service@2025-03-01-preview"
  resource_id = azurerm_api_management.this.id

  response_export_values = ["properties.privateIPAddresses"]

  timeouts {
    read = "5m"
  }

  depends_on = [
    azurerm_api_management.this,
  ]
}
