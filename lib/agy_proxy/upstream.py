import os
import aiohttp

class UpstreamTarget:
    def __init__(self, name: str, config: dict):
        self.name = name
        self.config = config
        self.url = config["url"]
        self.api_key_env = config.get("api_key_env", "")
        self.session = None

    async def get_session(self):
        if self.session is None:
            self.session = aiohttp.ClientSession()
        return self.session

    def transform_request(self, openai_body: dict) -> dict:
        """Transfoma payload OpenAI-compatible para formato do provider, se necessário."""
        import copy
        payload = copy.deepcopy(openai_body)
        
        # Mapeamento de modelo dinâmico
        model_mapping = self.config.get("transform", {}).get("model_mapping", {})
        requested_model = payload.get("model")
        
        if requested_model and requested_model in model_mapping:
            payload["model"] = model_mapping[requested_model]
            
        # TODO: Adicionar conversões para Anthropic API ou Gemini API (não-OpenAI)
        return payload

    def auth_headers(self) -> dict:
        api_key = os.environ.get(self.api_key_env, "")
        if self.name == "gemini":
            return {"x-goog-api-key": api_key}
        elif self.name == "claude":
            return {"x-api-key": api_key, "anthropic-version": "2023-06-01"}
        elif api_key:
            return {"Authorization": f"Bearer {api_key}"}
        return {}

    async def close(self):
        if self.session:
            await self.session.close()
            self.session = None
