export default {
  fetch(request: Request, env: Env): Response | Promise<Response> {
    const url = new URL(request.url);
    
    // Route /api/* to the backend
    if (url.pathname.startsWith('/api/')) {
      const apiUrl = new URL(url);
      apiUrl.host = new URL(env.API_ORIGIN).host;
      apiUrl.protocol = new URL(env.API_ORIGIN).protocol;
      
      return fetch(apiUrl, request);
    }
    
    // Everything else goes to SPA
		return new Response(null, { status: 404 });
  },
} satisfies ExportedHandler<Env>;
