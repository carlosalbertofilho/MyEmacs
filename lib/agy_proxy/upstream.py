import os
import aiohttp

class UpstreamTarget:
    def __init__(self, name: str, config: dict):
        self.name = name
        self.url = config["url"]
        self.api_key_env = config.get("api_key_env", "")
        self.session = None

    async def get_session(self):
        if self.session is None:
            self.session = aiohttp.ClientSession()
        return self.session

    def transform_request(self, openai_body: dict) -> dict:
        """Transfoma payload OpenAI-compatible para formato do provider, se necessário."""
        # TODO: Adicionar lógica específica para Anthropic/Gemini
        # Por enquanto, assumimos que o upstream é OpenAI compatible (ex: Ollama, vLLM, LiteLLM)
        return openai_body

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
