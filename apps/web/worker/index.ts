export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    
    console.log(`[Worker] Incoming request: ${request.method} ${url.href}`);
    
    // Route /api/* to the backend
    if (url.pathname.startsWith('/api')) {
      const apiUrl = new URL(env.API_ORIGIN);
      apiUrl.pathname = url.pathname.slice(4); // Remove '/api' prefix
      
      console.log(`[Worker] Proxying to: ${apiUrl.href}`);
      
      // Create new request with corrected URL and headers
      const apiRequest = new Request(apiUrl, {
        method: request.method,
        body: request.body,
      });
      
      try {
        const response = await fetch(apiRequest);
        console.log(`[Worker] API response: ${response.status}`);
        return response;
      } catch (error: unknown) {
        if (error instanceof Error) {
          console.error(`[Worker] Fetch error: ${error.message}`);
          return new Response(`Fetch error: ${error.message}`, { status: 502 });
        } else {
          console.error(`[Worker] Fetch error: ${String(error)}`);
          return new Response(`Fetch error: ${String(error)}`, { status: 502 });
        }
      }
    }

    // Everything else goes to SPA: delegate to Cloudflare asset handling (SPA behavior configured in wrangler.jsonc)
    return (env as any).ASSETS.fetch(request);
  },
} satisfies ExportedHandler<Env>;
