export const fetchNoStore = (
  input: RequestInfo | URL,
  init: RequestInit = {}
): Promise<Response> => {
  return fetch(input, {
    ...init,
    cache: 'no-store',
  });
};
