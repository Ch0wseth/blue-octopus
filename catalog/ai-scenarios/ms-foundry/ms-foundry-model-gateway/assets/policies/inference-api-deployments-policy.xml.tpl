<policies>
    <inbound>
        <base />
        <set-backend-service backend-id="${foundry_openai_backend_name}" />
        <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
