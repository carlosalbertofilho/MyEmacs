from aiohttp import web
import json
import os

from .router import RouterFSM

async def health_check(request):
    return web.json_response({"status": "ok", "version": "1.0.0"})

async def list_models(request):
    config = request.app["config"]
    providers = config.get("providers", {})
    
    models = []
    for provider_name, provider_data in providers.items():
        provider_models = provider_data.get("models", [])
        for model_id in provider_models:
            models.append({
                "id": model_id,
                "object": "model",
                "created": 1686935002,
                "owned_by": provider_name
            })
            
    return web.json_response({
        "object": "list",
        "data": models
    })

async def proxy_handler(request):
    config = request.app["config"]
    
    # Simple model extraction from JSON body
    try:
        body = await request.json()
    except Exception:
        body = {}
        
    requested_model = body.get("model")
    if not requested_model:
        return web.json_response({"error": "Model not specified in request body"}, status=400)
    
    router = request.app["router"]
    target_provider = request.headers.get("X-Agy-Provider", "auto")
    
    return await router.handle_chat_completion(request, body, target_provider)

def create_app(config):
    app = web.Application()
    app["config"] = config
    app["router"] = RouterFSM(config)
    
    app.router.add_get('/health', health_check)
    app.router.add_get('/v1/models', list_models)
    app.router.add_post('/v1/chat/completions', proxy_handler)
    app.router.add_route('*', '/{tail:.*}', proxy_handler)
    
    return app
