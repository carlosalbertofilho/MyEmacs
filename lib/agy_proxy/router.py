import asyncio
import json
import logging
from aiohttp import web
from typing import Dict, Any

from .upstream import UpstreamTarget
from .tool_bridge import inject_tools, handle_tool_calls

logger = logging.getLogger(__name__)

class RouterFSM:
    def __init__(self, config: dict):
        self.config = config
        self.providers: Dict[str, UpstreamTarget] = {}
        self._init_providers()

    def _init_providers(self):
        providers_conf = self.config.get("providers", {})
        for name, conf in providers_conf.items():
            self.providers[name] = UpstreamTarget(name, conf)

    async def resolve(self, requested_provider: str, model: str) -> UpstreamTarget:
        """Resolve qual upstream usar, incluindo lógica FSM e fallback no futuro."""
        if requested_provider in self.providers:
            return self.providers[requested_provider]
            
        # Fallback to discover by model
        for name, provider in self.providers.items():
            if model in self.config.get("providers", {}).get(name, {}).get("models", []):
                return provider
                
        # Default fallback
        return next(iter(self.providers.values())) if self.providers else None

    async def handle_chat_completion(self, request: web.Request, body: dict, provider_name: str) -> web.Response:
        """
        Intermediates the chat completion.
        1. Injects tools.
        2. Sends to upstream.
        3. If tool calls returned, execute them and recurse.
        4. Otherwise return to client.
        """
        model = body.get("model", "")
        upstream = await self.resolve(provider_name, model)
        if not upstream:
            return web.json_response({"error": "No upstream available"}, status=503)

        # 1. Inject tools
        body = inject_tools(body)

        is_stream = body.get("stream", False)

        # Se for streaming, repassamos a complexidade de tool calls chunked
        # no futuro. Para simplificar inicialmente, forçamos o stream a funcionar
        # como um passthrough ou acumulamos os tool calls.
        if is_stream:
            return await self._relay_stream(request, upstream, body)
        else:
            return await self._relay_json(request, upstream, body)

    async def _relay_json(self, request: web.Request, upstream: UpstreamTarget, body: dict) -> web.Response:
        session = await upstream.get_session()
        payload = upstream.transform_request(body)
        
        async with session.post(upstream.url, json=payload, headers=upstream.auth_headers()) as resp:
            resp_json = await resp.json()

        # Verifica se houve tool_calls
        choice = resp_json.get("choices", [{}])[0]
        msg = choice.get("message", {})
        
        if msg.get("tool_calls"):
            logger.info("Intercepting tool calls...")
            tool_results = await handle_tool_calls(msg)
            
            # Appenda na conversa original: a mensagem assistant + tool results
            if "messages" not in body:
                body["messages"] = []
            
            body["messages"].append(msg)
            body["messages"].extend(tool_results)
            
            # Recurse: faz nova chamada para o LLM resolver o resultado
            return await self._relay_json(request, upstream, body)

        return web.json_response(resp_json, status=200)

    async def _relay_stream(self, request: web.Request, upstream: UpstreamTarget, body: dict) -> web.StreamResponse:
        session = await upstream.get_session()
        payload = upstream.transform_request(body)
        
        response = web.StreamResponse(
            status=200,
            headers={
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            }
        )
        await response.prepare(request)
        
        async with session.post(upstream.url, json=payload, headers=upstream.auth_headers()) as resp:
            async for chunk in resp.content.iter_any():
                await response.write(chunk)
                
        await response.write_eof()
        return response
