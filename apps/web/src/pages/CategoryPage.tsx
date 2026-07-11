import { useEffect, useState } from 'react';
import type { Category } from '../api';
import { OpenAPI } from '../api/core/OpenAPI';
import CacheInfo from '../components/CacheInfo';
import { fetchNoStore } from '../utils/fetchNoStore';
import { headersFromResponse } from '../utils/headersFromResponse';

export default function CategoryPage() {
	const [categories, setCategories] = useState<Category[]>([]);
	const [headers, setHeaders] = useState<Record<string, string>>({});
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState<string | null>(null);

	useEffect(() => {
		const fetchData = async () => {
			try {
				setLoading(true);
				setError(null);

				const response = await fetchNoStore(`${OpenAPI.BASE}/category`);
				setHeaders(headersFromResponse(response));

				if (!response.ok) {
					throw new Error(`HTTP ${response.status} ${response.statusText}`.trim());
				}

				const result = await response.json();
				setCategories(result.categories || []);
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

	return (
		<div className="page">
			<div className="container">
				<h2>📂 Categories</h2>

				<div className="page-layout">
					<div className="page-main">
						<div className="content-section">
							<div className="categories-grid">
								{categories.map((category) => (
									<div key={category.slug} className="category-card">
										<h3>{category.name}</h3>
										<p>{category.description}</p>
										{category.productCount && category.productCount > 0 && (
											<p className="category-count">
												{category.productCount} product{category.productCount !== 1 ? 's' : ''}
											</p>
										)}
									</div>
								))}
							</div>

							{categories.length === 0 && <div className="empty-state">No categories found</div>}
						</div>
					</div>
					<aside className="page-aside">
						<CacheInfo headers={headers} />
					</aside>
				</div>
			</div>
		</div>
	);
}
