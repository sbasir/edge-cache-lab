import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import type { Homepage } from '../api';
import { OpenAPI } from '../api/core/OpenAPI';
import CacheInfo from '../components/CacheInfo';
import { fetchNoStore } from '../utils/fetchNoStore';

export default function HomePage() {
	const [data, setData] = useState<Homepage | null>(null);
	const [headers, setHeaders] = useState<Record<string, string>>({});
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState<string | null>(null);

	useEffect(() => {
		const fetchData = async () => {
			try {
				setLoading(true);
				setError(null);

				const response = await fetchNoStore(`${OpenAPI.BASE}/`);
				const headersObj: Record<string, string> = {};
				response.headers.forEach((value, key) => {
					headersObj[key] = value;
				});
				setHeaders(headersObj);

				if (!response.ok) {
					throw new Error(`HTTP ${response.status} ${response.statusText}`.trim());
				}

				const result = await response.json();
				setData(result);
			} catch (err) {
				setError(err instanceof Error ? err.message : 'Failed to fetch');
			} finally {
				setLoading(false);
			}
		};

		fetchData();
	}, []);

	if (loading) return <div className="loading">Loading...</div>;
	if (error) return <div className="error">Error: {error}</div>;
	if (!data) return <div className="error">No data</div>;

	return (
		<div className="page">
			<div className="container">
				<div className="page-layout">
					<div className="page-main">
						<div className="products-section">
							<h2 className="section-title">Featured Products</h2>
							<p className="section-subtitle">Click any product to see cache behavior in action</p>
							{data.featured && data.featured.length > 0 ? (
								<div className="products">
									{data.featured.map((product) => (
										<Link key={product.id} to={`/product/${product.id}`} className="product-card">
											<div className="product-image-placeholder">{product.name.charAt(0)}</div>
											<div className="product-details">
												<h5>{product.name}</h5>
												<p className="product-slug">{product.slug}</p>
												<p className="price">${product.price}</p>
												<span className={`stock ${product.inStock ? 'in-stock' : 'out-of-stock'}`}>
													{product.inStock ? '✓ In Stock' : '✗ Out of Stock'}
												</span>
											</div>
										</Link>
									))}
								</div>
							) : (
								<div className="empty-state">No featured products yet</div>
							)}
						</div>
					</div>
					<aside className="page-aside">
						<CacheInfo meta={data.meta} headers={headers} />
					</aside>
				</div>
			</div>
		</div>
	);
}
