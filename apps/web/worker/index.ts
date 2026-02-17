export default {
  fetch(request: Request, env: Env): Response | Promise<Response> {
    const url = new URL(request.url);
    
    // Route /api/* to the backend
    if (url.pathname.startsWith('/api')) {
      const apiUrl = new URL(env.API_ORIGIN);
      apiUrl.pathname = url.pathname.slice(4); // Remove '/api' prefix
      apiUrl.search = url.search;
      
      return fetch(apiUrl, request);
    }

    // Everything else goes to SPA: delegate to Cloudflare asset handling (SPA behavior configured in wrangler.jsonc)
    return (env as any).ASSETS.fetch(request);
  },
} satisfies ExportedHandler<Env>;
