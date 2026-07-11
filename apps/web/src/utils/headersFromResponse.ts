// Flattens Response headers into a serializable object for CacheInfo rendering.
export const headersFromResponse = (response: Response): Record<string, string> => {
	const headers: Record<string, string> = {};
	response.headers.forEach((value, key) => {
		headers[key] = value;
	});
	return headers;
};
