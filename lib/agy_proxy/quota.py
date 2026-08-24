import time
import logging
from dataclasses import dataclass, field
from typing import Dict, Optional
from multidict import CIMultiDictProxy

logger = logging.getLogger(__name__)

@dataclass
class QuotaInfo:
    provider: str
    requests_limit: int = 0
    requests_used: int = 0
    tokens_limit: int = 0
    tokens_used: int = 0
    reset_at: Optional[float] = None
    last_updated: float = field(default_factory=time.time)
    
    @property
    def quota_remaining_pct(self) -> float:
        if self.requests_limit == 0:
            return 100.0
        remaining = max(0, self.requests_limit - self.requests_used)
        return (remaining / self.requests_limit) * 100.0

class QuotaMonitor:
    def __init__(self, config: dict):
        self.config = config.get("quota", {})
        self.warning_threshold = self.config.get("warning_threshold_pct", 25)
        self.critical_threshold = self.config.get("critical_threshold_pct", 10)
        self.store: Dict[str, QuotaInfo] = {}

    def get_info(self, provider: str) -> QuotaInfo:
        if provider not in self.store:
            self.store[provider] = QuotaInfo(provider=provider)
        return self.store[provider]

    def update_from_headers(self, provider: str, headers: CIMultiDictProxy) -> None:
        """Parses x-ratelimit headers and updates the quota store."""
        info = self.get_info(provider)
        
        def _get_int(key: str) -> Optional[int]:
            val = headers.get(key)
            if val and val.isdigit():
                return int(val)
            return None

        def _get_float(key: str) -> Optional[float]:
            val = headers.get(key)
            try:
                if val:
                    return float(val)
            except ValueError:
                pass
            return None

        # Common rate limit headers (OpenAI/Anthropic/Gemini equivalents)
        req_limit = _get_int("x-ratelimit-limit-requests")
        req_remain = _get_int("x-ratelimit-remaining-requests")
        tok_limit = _get_int("x-ratelimit-limit-tokens")
        tok_remain = _get_int("x-ratelimit-remaining-tokens")
        reset_requests = _get_float("x-ratelimit-reset-requests")

        updated = False
        if req_limit is not None:
            info.requests_limit = req_limit
            updated = True
        if req_remain is not None and info.requests_limit > 0:
            info.requests_used = max(0, info.requests_limit - req_remain)
            updated = True
            
        if tok_limit is not None:
            info.tokens_limit = tok_limit
            updated = True
        if tok_remain is not None and info.tokens_limit > 0:
            info.tokens_used = max(0, info.tokens_limit - tok_remain)
            updated = True
            
        if reset_requests is not None:
            info.reset_at = time.time() + reset_requests
            updated = True
            
        if updated:
            info.last_updated = time.time()
            logger.debug(f"Updated quota info for {provider}: {info.quota_remaining_pct:.1f}% remaining")

# Singleton-like instantiation is possible, but we'll attach it to the app or router
