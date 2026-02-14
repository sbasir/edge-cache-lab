import type { ResponseMeta } from '../api';

interface CacheInfoProps {
  meta?: ResponseMeta;
  headers?: Record<string, string>;
}

export default function CacheInfo({ meta, headers }: CacheInfoProps) {
  if (!meta && !headers) return null;

  const xCache = headers?.['x-cache'] || headers?.['X-Cache'] || 'N/A';
  const cacheControl = headers?.['cache-control'] || headers?.['Cache-Control'];
  const etag = headers?.['etag'] || headers?.['ETag'];
  const requestId = headers?.['x-request-id'] || headers?.['X-Request-Id'];

  return (
    <div className="cache-info">
      <h3>📊 Cache Behavior</h3>
      <div className="cache-details">
        <div className="cache-item">
          <span className="cache-label">Cache Status:</span>
          <span className={`cache-value cache-status-${xCache.toLowerCase()}`}>
            {xCache}
          </span>
        </div>
        {cacheControl && (
          <div className="cache-item">
            <span className="cache-label">Cache-Control:</span>
            <span className="cache-value">{cacheControl}</span>
          </div>
        )}
        {etag && (
          <div className="cache-item">
            <span className="cache-label">ETag:</span>
            <span className="cache-value">{etag}</span>
          </div>
        )}
        {requestId && (
          <div className="cache-item">
            <span className="cache-label">Request ID:</span>
            <span className="cache-value">{requestId}</span>
          </div>
        )}
      </div>
      {meta && (
        <div className="response-meta">
          <h4>Response Metadata</h4>
          <pre>{JSON.stringify(meta, null, 2)}</pre>
        </div>
      )}
    </div>
  );
}
