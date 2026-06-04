"""
Test: Appel direct APIM avec JWT Entra ID uniquement (sans subscription key)
Simule le comportement de l'Agent Service en mode ProjectManagedIdentity.
Ajoute un header custom X-Agent-Id pour différencier les agents.
"""

import os
import sys
import time

import requests
from azure.identity import AzureCliCredential, AzureDeveloperCliCredential, ChainedTokenCredential
from dotenv import load_dotenv

load_dotenv()

apim_resource_gateway_url = os.environ["APIM_RESOURCE_GATEWAY_URL"]
foundry_model_name = os.getenv("FOUNDRY_MODEL_NAME", "gpt-5.4-mini")
openai_api_version = os.getenv("OPENAI_API_VERSION", "2024-12-01-preview")

# Agent ID passed as argument or default
agent_id = sys.argv[1] if len(sys.argv) > 1 else "agent-default"

# Get JWT token with cognitiveservices audience (same as managed identity would use)
credential = ChainedTokenCredential(AzureCliCredential(), AzureDeveloperCliCredential())
jwt_token = credential.get_token("https://cognitiveservices.azure.com/.default").token
print(f"🔐 JWT token acquired (audience: cognitiveservices.azure.com)")
print(f"🤖 Agent ID: {agent_id}\n")

# Call APIM with JWT ONLY + custom X-Agent-Id header
url = f"{apim_resource_gateway_url}/inference/models/deployments/{foundry_model_name}/chat/completions?api-version={openai_api_version}"

headers = {
    "Authorization": f"Bearer {jwt_token}",
    "Content-Type": "application/json",
    "X-Agent-Id": agent_id,
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
    print(f"\n🎉 JWT-only auth works! Agent '{agent_id}' identified via X-Agent-Id header.")
elif response.status_code == 429:
    print(f"🚫 Rate limited! Agent '{agent_id}' hit TPM quota.")
else:
    print(f"❌ Error: {response.text[:300]}")
    if response.status_code == 401:
        print("\n💡 APIM rejected the token. Check:")
        print("   - subscription_required must be false")
        print("   - validate-azure-ad-token policy must accept cognitiveservices.azure.com audience")
