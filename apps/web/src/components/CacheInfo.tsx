import { useState } from 'react';

const CACHE_STATUS_MAP: Record<string, string> = {
	HIT: 'hit',
	MISS: 'miss',
	PASS: 'pass'
};

const sanitizeCacheStatus = (status: string): string => {
	const normalized = status.toUpperCase().trim();
	return CACHE_STATUS_MAP[normalized] || 'unknown';
};

import type { ResponseMeta } from '../api';

interface CacheInfoProps {
	meta?: ResponseMeta;
	headers?: Record<string, string>;
}

export default function CacheInfo({ meta, headers }: CacheInfoProps) {
	const [isMetaOpen, setIsMetaOpen] = useState(false);

	// Early return after hooks to comply with Rules of Hooks
	const hasData = meta || headers;

	const xCache = headers?.['x-cache'] || headers?.['X-Cache'] || 'N/A';
	const cacheControl = headers?.['cache-control'] || headers?.['Cache-Control'];
	const etag = headers?.etag || headers?.ETag;
	const requestId = headers?.['x-request-id'] || headers?.['X-Request-Id'];

	if (!hasData) return null;

	return (
		<div className="cache-info">
			<h3>📊 Cache Behavior</h3>
			<div className="cache-details">
				<div className="cache-item">
					<span className="cache-label">Cache Status:</span>
					<span className={`cache-value cache-status-${sanitizeCacheStatus(xCache)}`}>
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
					<button
						type="button"
						className="response-meta-toggle"
						onClick={() => setIsMetaOpen((open) => !open)}
						aria-expanded={isMetaOpen}
					>
						<span className="toggle-icon" aria-hidden="true">
							{isMetaOpen ? 'v' : '>'}
						</span>
						Response Metadata
					</button>
					{isMetaOpen && <pre>{JSON.stringify(meta, null, 2)}</pre>}
				</div>
			)}
		</div>
	);
}
