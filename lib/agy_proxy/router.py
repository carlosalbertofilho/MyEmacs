import asyncio
import json
import logging
import enum
import time
from aiohttp import web
from typing import Dict, Any, Optional

from .upstream import UpstreamTarget
from .tool_bridge import inject_tools, handle_tool_calls
from .quota import QuotaMonitor

logger = logging.getLogger(__name__)

class FSMState(enum.Enum):
    NORMAL = "normal"
    THROTTLED = "throttled"
    FALLBACK = "fallback"
    DEGRADED = "degraded"

class RouterFSM:
    def __init__(self, config: dict):
        self.config = config
        self.providers: Dict[str, UpstreamTarget] = {}
        self.quota_monitor = QuotaMonitor(config)
        self.state: FSMState = FSMState.NORMAL
        self._lock = asyncio.Lock()
        
        # Determine fallback chain from config (defaulting to gemini -> claude -> ollama)
        self.fallback_chain = self.config.get("quota", {}).get("fallback_chain", ["gemini", "claude", "ollama"])
        self.primary_provider = self.fallback_chain[0] if self.fallback_chain else "gemini"
        
        # Status tracking
        self.provider_status: Dict[str, dict] = {}
        
        self._init_providers()

    def _init_providers(self):
        providers_conf = self.config.get("providers", {})
        for name, conf in providers_conf.items():
            self.providers[name] = UpstreamTarget(name, conf)
            self.provider_status[name] = {
                "available": True,
                "consecutive_errors": 0,
                "retry_after": 60.0
            }

    def _mark_down(self, provider_name: str, retry_after: float = 60.0):
        if provider_name in self.provider_status:
            self.provider_status[provider_name]["available"] = False
            self.provider_status[provider_name]["consecutive_errors"] += 1
            self.provider_status[provider_name]["retry_after"] = retry_after
            logger.warning(f"Provider {provider_name} marked DOWN.")

    def _mark_up(self, provider_name: str):
        if provider_name in self.provider_status:
            self.provider_status[provider_name]["available"] = True
            self.provider_status[provider_name]["consecutive_errors"] = 0
            logger.info(f"Provider {provider_name} marked UP.")

    def _has_available_fallback(self) -> bool:
        for p in self.fallback_chain:
            if p != "ollama" and self.provider_status.get(p, {}).get("available", False):
                return True
        return False

    async def _transition(self, new_state: FSMState):
        old_state = self.state
        self.state = new_state
        logger.info(f"FSM Transition: {old_state.value} -> {new_state.value}")

    async def handle_event(self, event: str, provider: str = "", **kwargs):
        """Processes events and transitions FSM states."""
        async with self._lock:
            if event == "rate_limited":
                retry_after = kwargs.get("retry_after", 60)
                self._mark_down(provider, retry_after)
                
                if self.state == FSMState.NORMAL:
                    if self._has_available_fallback():
                        await self._transition(FSMState.THROTTLED)
                    else:
                        await self._transition(FSMState.DEGRADED)
                elif self.state == FSMState.THROTTLED:
                    if self._has_available_fallback():
                        await self._transition(FSMState.FALLBACK)
                    else:
                        await self._transition(FSMState.DEGRADED)
            elif event == "quota_restored":
                self._mark_up(provider)
                if self.provider_status.get(self.primary_provider, {}).get("available", False):
                    await self._transition(FSMState.NORMAL)
                elif self._has_available_fallback():
                    await self._transition(FSMState.FALLBACK)

    async def resolve(self, requested_provider: str, model: str) -> Optional[UpstreamTarget]:
        """Resolves which upstream to use based on the FSM state."""
        async with self._lock:
            # Explicit user override always wins if available
            if requested_provider != "auto" and requested_provider in self.providers:
                if self.provider_status.get(requested_provider, {}).get("available", False):
                    return self.providers[requested_provider]
            
            # FSM State Resolution
            if self.state == FSMState.NORMAL:
                return self.providers.get(self.primary_provider)
                
            elif self.state in (FSMState.THROTTLED, FSMState.FALLBACK):
                for name in self.fallback_chain:
                    if self.provider_status.get(name, {}).get("available", False):
                        return self.providers.get(name)
                # If we get here, no fallbacks are available
                await self._transition(FSMState.DEGRADED)
                return self.providers.get("ollama")
                
            elif self.state == FSMState.DEGRADED:
                return self.providers.get("ollama")

        return None

    async def handle_chat_completion(self, request: web.Request, body: dict, provider_name: str) -> web.Response:
        model = body.get("model", "")
        upstream = await self.resolve(provider_name, model)
        if not upstream:
            return web.json_response({"error": "No upstream available"}, status=503)

        body = inject_tools(body)
        is_stream = body.get("stream", False)

        if is_stream:
            return await self._relay_stream(request, upstream, body)
        else:
            return await self._relay_json(request, upstream, body)

    async def _relay_json(self, request: web.Request, upstream: UpstreamTarget, body: dict) -> web.Response:
        session = await upstream.get_session()
        payload = upstream.transform_request(body)
        
        async with session.post(upstream.url, json=payload, headers=upstream.auth_headers()) as resp:
            # Quota extraction
            self.quota_monitor.update_from_headers(upstream.name, resp.headers)
            
            if resp.status == 429:
                retry_after = int(resp.headers.get("retry-after", "60"))
                await self.handle_event("rate_limited", provider=upstream.name, retry_after=retry_after)
                # Retry transparently with resolved fallback
                return await self.handle_chat_completion(request, body, "auto")
                
            if resp.status >= 400:
                resp_text = await resp.text()
                return web.json_response({"error": "Upstream error", "details": resp_text}, status=resp.status)
                
            resp_json = await resp.json()

        choice = resp_json.get("choices", [{}])[0]
        msg = choice.get("message", {})
        
        if msg.get("tool_calls"):
            logger.info("Intercepting tool calls...")
            tool_results = await handle_tool_calls(msg)
            
            if "messages" not in body:
                body["messages"] = []
            
            body["messages"].append(msg)
            body["messages"].extend(tool_results)
            
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
            self.quota_monitor.update_from_headers(upstream.name, resp.headers)
            
            if resp.status == 429:
                # Can't easily retry if headers are already prepared and sent to client.
                # However, since we haven't sent chunks yet, we could theoretically redirect, 
                # but web.StreamResponse cannot be easily reset if prepared.
                # For Phase 4, we fail gracefully.
                await self.handle_event("rate_limited", provider=upstream.name)
                await response.write(b'data: {"error": "Rate limited. Retrying on next request."}\n\n')
                await response.write_eof()
                return response

            async for chunk in resp.content.iter_any():
                await response.write(chunk)
                
        await response.write_eof()
        return response
