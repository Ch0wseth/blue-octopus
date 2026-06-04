<policies>
    <inbound>
        <base />
        <!-- Validate JWT token issued by Microsoft Entra ID (only if Authorization header is present) -->
        <choose>
            <when condition="@(context.Request.Headers.ContainsKey(&quot;Authorization&quot;))">
                <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized. Valid JWT token required." require-expiration-time="true" require-scheme="Bearer" require-signed-tokens="true" output-token-variable-name="jwt">
                    <openid-config url="https://login.microsoftonline.com/${tenant-id}/v2.0/.well-known/openid-configuration" />
                    <audiences>
                        <audience>https://management.azure.com</audience>
                        <audience>https://ai.azure.com</audience>
                        <audience>https://cognitiveservices.azure.com</audience>
                    </audiences>
                    <issuers>
                        <issuer>https://sts.windows.net/${tenant-id}/</issuer>
                        <issuer>https://login.microsoftonline.com/${tenant-id}/v2.0</issuer>
                    </issuers>
                </validate-jwt>
            </when>
        </choose>

        <!-- Extract username and app id from the JWT token for telemetry -->
        <set-variable name="username" value="@{
            try {
                if (!context.Variables.ContainsKey("jwt")) { return "api-key-user"; }
                Jwt jwt = (Jwt)context.Variables["jwt"];
                if (jwt.Claims.ContainsKey("upn") && jwt.Claims["upn"].Count() > 0) {
                    return jwt.Claims["upn"][0];
                }
                if (jwt.Claims.ContainsKey("unique_name") && jwt.Claims["unique_name"].Count() > 0) {
                    return jwt.Claims["unique_name"][0];
                }
                if (jwt.Claims.ContainsKey("preferred_username") && jwt.Claims["preferred_username"].Count() > 0) {
                    return jwt.Claims["preferred_username"][0];
                }
                if (jwt.Claims.ContainsKey("email") && jwt.Claims["email"].Count() > 0) {
                    return jwt.Claims["email"][0];
                }
                return jwt.Subject ?? "unknown";
            }
            catch {
                return "error";
            }
        }" />
        <set-variable name="app-id" value="@{
            try {
                if (!context.Variables.ContainsKey("jwt")) { return context.Subscription.Id; }
                Jwt jwt = (Jwt)context.Variables["jwt"];
                return jwt.Claims.ContainsKey("appid") ? jwt.Claims["appid"][0] : "unknown";
            }
            catch {
                return "error";
            }
        }" />
        <!-- Emit usage custom metric-->
        <emit-metric name="FoundryModelsRequest" value="1" namespace="FoundryModel">
            <dimension name="username" value="@((string)context.Variables["username"])" />
            <dimension name="app_id" value="@((string)context.Variables["app-id"])" />
            <dimension name="operation" value="@(context.Operation.Name)" />
            <dimension name="api_name" value="@(context.Api.Name)" />
        </emit-metric>
        <llm-emit-token-metric namespace="FoundryModelLLMRequest">
            <dimension name="username" value="@((string)context.Variables["username"])" />
            <dimension name="Client IP" value="@(context.Request.IpAddress)" />
            <dimension name="app_id" value="@((string)context.Variables["app-id"])" />
        </llm-emit-token-metric>
        <!-- Route to correct backend based on path type -->
        <choose>
            <!-- OpenAI-style calls (e.g. /deployments/{model}/chat/completions from Agent SDK) -->
            <when condition="@(context.Request.Url.Path.Contains("/deployments/"))">
                <set-backend-service base-url="${foundry_openai_backend_url}" />
                <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
            </when>
            <!-- Model Inference API calls (e.g. /chat/completions from main.py) -->
            <otherwise>
                <set-backend-service backend-id="${foundry_backend_name}" />
            </otherwise>
        </choose>
        <!-- Token rate limiting per application identity (from JWT appid) -->
        <choose>
            <!-- Projet Agent (managed identity) -->
            <when condition="@((string)context.Variables[&quot;app-id&quot;] == &quot;${identity_dev_client_id}&quot;)">
                <llm-token-limit counter-key="@((string)context.Variables[&quot;app-id&quot;])"
                    tokens-per-minute="${tokens_per_minute_dev}" estimate-prompt-tokens="false" remaining-tokens-variable-name="remainingTokens">
                </llm-token-limit>
            </when>
            <!-- Autres appelants (main.py, etc.) -->
            <otherwise>
                <llm-token-limit counter-key="@((string)context.Variables[&quot;app-id&quot;])"
                    tokens-per-minute="${tokens_per_minute_com}" estimate-prompt-tokens="false" remaining-tokens-variable-name="remainingTokens">
                </llm-token-limit>
            </otherwise>
        </choose>
        <!-- Remove api-key header, as Foundry model does not need it -->
        <set-header name="api-key" exists-action="delete" />
        <!-- Check if the request is a streaming request by looking for "stream" property in the JSON body -->
        <choose>
            <when condition="@(context.Request.Body.As<JObject>(true)["stream"] != null && context.Request.Body.As<JObject>(true)["stream"].Type != JTokenType.Null)">
                <set-variable name="isStream" value="@{
                    var content = (context.Request.Body?.As<JObject>(true));
                    string streamValue = content["stream"].ToString();
                    return streamValue;
                }" />
            </when>
        </choose>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <!-- Set x-ms-stream header in the response if the request is a streaming request, so that the client can handle the response accordingly -->
        <set-header name="x-ms-stream" exists-action="override">
            <value>@{
                    return context.Variables.GetValueOrDefault<string>("isStream","false").Equals("true", StringComparison.OrdinalIgnoreCase).ToString();
                }</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>