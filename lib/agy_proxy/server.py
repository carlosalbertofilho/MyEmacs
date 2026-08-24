from aiohttp import web
import os

async def health_check(request):
    return web.json_response({"status": "ok", "version": "1.0.0"})

async def proxy_handler(request):
    return web.json_response({"error": "Not implemented yet"}, status=501)

def create_app(config):
    app = web.Application()
    app["config"] = config
    
    app.router.add_get('/health', health_check)
    app.router.add_route('*', '/{tail:.*}', proxy_handler)
    
    return app
