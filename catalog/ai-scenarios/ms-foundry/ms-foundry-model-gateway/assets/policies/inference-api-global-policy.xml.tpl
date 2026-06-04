<policies>
    <inbound>
        <base />
        <!-- Dual authentication: Subscription Key OR JWT Entra ID -->
        <choose>
            <!-- Path 1: No subscription key → validate Entra ID token (Agent Service with managed identity) -->
            <when condition="@(context.Subscription == null)">
                <validate-azure-ad-token tenant-id="${tenant-id}" header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized. Valid Entra ID token required." output-token-variable-name="jwt">
                    <audiences>
                        <audience>https://cognitiveservices.azure.com</audience>
                    </audiences>
                </validate-azure-ad-token>
            </when>
            <!-- Path 2: Subscription key present → validate JWT if Authorization header exists (main.py, dev tools) -->
            <otherwise>
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
            </otherwise>
        </choose>

        <!-- Extract caller identity from JWT for telemetry and rate limiting -->
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
                if (!context.Variables.ContainsKey("jwt")) { return context.Subscription != null ? context.Subscription.Id : "unknown"; }
                Jwt jwt = (Jwt)context.Variables["jwt"];
                // For managed identity tokens, use xms_mirid (project resource ID)
                if (jwt.Claims.ContainsKey("xms_mirid") && jwt.Claims["xms_mirid"].Count() > 0) {
                    return jwt.Claims["xms_mirid"][0];
                }
                // For user tokens, use appid
                if (jwt.Claims.ContainsKey("appid") && jwt.Claims["appid"].Count() > 0) {
                    return jwt.Claims["appid"][0];
                }
                return "unknown";
            }
            catch {
                return "error";
            }
        }" />
        <!-- Extract agent identifier from custom header (if present) -->
        <set-variable name="agent-id" value="@(context.Request.Headers.GetValueOrDefault("X-Agent-Id", "unknown"))" />
        <!-- Emit usage custom metric-->
        <emit-metric name="FoundryModelsRequest" value="1" namespace="FoundryModel">
            <dimension name="username" value="@((string)context.Variables["username"])" />
            <dimension name="app_id" value="@((string)context.Variables["app-id"])" />
            <dimension name="agent_id" value="@((string)context.Variables["agent-id"])" />
            <dimension name="operation" value="@(context.Operation.Name)" />
            <dimension name="api_name" value="@(context.Api.Name)" />
        </emit-metric>
        <llm-emit-token-metric namespace="FoundryModelLLMRequest">
            <dimension name="username" value="@((string)context.Variables["username"])" />
            <dimension name="Client IP" value="@(context.Request.IpAddress)" />
            <dimension name="app_id" value="@((string)context.Variables["app-id"])" />
            <dimension name="agent_id" value="@((string)context.Variables["agent-id"])" />
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
        <!-- Token rate limiting per caller identity (xms_mirid for projects, appid for users) -->
        <choose>
            <!-- Foundry Project (managed identity with xms_mirid) -->
            <when condition="@(((string)context.Variables[&quot;app-id&quot;]).Contains(&quot;/projects/&quot;))">
                <llm-token-limit counter-key="@((string)context.Variables[&quot;app-id&quot;])"
                    tokens-per-minute="${tokens_per_minute_dev}" estimate-prompt-tokens="false" remaining-tokens-variable-name="remainingTokens">
                </llm-token-limit>
            </when>
            <!-- Other callers (main.py, dev tools with appid) -->
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