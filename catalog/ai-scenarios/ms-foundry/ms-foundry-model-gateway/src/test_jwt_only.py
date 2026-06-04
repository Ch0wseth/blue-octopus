"""
Test: Appel direct APIM avec JWT Entra ID uniquement (sans subscription key)
Simule le comportement attendu de l'Agent Service en mode AAD.
"""

import os
import time

import requests
from azure.identity import AzureCliCredential, AzureDeveloperCliCredential, ChainedTokenCredential
from dotenv import load_dotenv

load_dotenv()

apim_resource_gateway_url = os.environ["APIM_RESOURCE_GATEWAY_URL"]
foundry_model_name = os.getenv("FOUNDRY_MODEL_NAME", "gpt-5.4-mini")
openai_api_version = os.getenv("OPENAI_API_VERSION", "2024-12-01-preview")

# Get JWT token with cognitiveservices audience (same as managed identity would use)
credential = ChainedTokenCredential(AzureCliCredential(), AzureDeveloperCliCredential())
jwt_token = credential.get_token("https://cognitiveservices.azure.com/.default").token
print("🔐 JWT token acquired (audience: cognitiveservices.azure.com)\n")

# Call APIM with JWT ONLY — no subscription key
url = f"{apim_resource_gateway_url}/inference/models/deployments/{foundry_model_name}/chat/completions?api-version={openai_api_version}"

headers = {
    "Authorization": f"Bearer {jwt_token}",
    "Content-Type": "application/json",
}

payload = {
    "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Say hello in French."},
    ],
    "stream": False,
}

print(f"🚀 Calling APIM with JWT only (no api-key)...")
print(f"   URL: {url}\n")

start = time.time()
response = requests.post(url, headers=headers, json=payload)
elapsed = time.time() - start

print(f"📊 Status: {response.status_code} | {elapsed:.1f}s")

if response.status_code == 200:
    data = response.json()
    content = data["choices"][0]["message"]["content"]
    print(f"✅ Response: {content}")
    print(f"\n🎉 JWT-only auth works! Agent Service AAD pattern is viable.")
else:
    print(f"❌ Error: {response.text[:300]}")
    if response.status_code == 401:
        print("\n💡 APIM rejected the token. Check:")
        print("   - subscription_required must be false")
        print("   - validate-azure-ad-token policy must accept cognitiveservices.azure.com audience")
