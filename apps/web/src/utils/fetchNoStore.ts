// Ensures browser-side caching does not hide real CDN/Varnish behavior in the lab UI.
export const fetchNoStore = (
	input: RequestInfo | URL,
	init: RequestInit = {}
): Promise<Response> => {
	return fetch(input, {
		...init,
		cache: 'no-store'
	});
};
