import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import type { Homepage } from '../api';
import { OpenAPI } from '../api/core/OpenAPI';
import CacheInfo from '../components/CacheInfo';
import { fetchNoStore } from '../utils/fetchNoStore';
import { headersFromResponse } from '../utils/headersFromResponse';

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
        
        // Capture response headers by using fetch directly
        const response = await fetchNoStore(`${OpenAPI.BASE}/`);
        setHeaders(headersFromResponse(response));
        
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
        <h2>🏠 Home Page</h2>

        <div className="page-layout">
          <div className="page-main">
            <div className="content-section">
              <h3>Welcome to Edge Cache Lab</h3>
              <p>{data.title}</p>
              
              {data.featured && data.featured.length > 0 && (
                <div className="products-grid">
                  <h4>Featured Products</h4>
                  <div className="products">
                    {data.featured.map((product) => (
                      <Link key={product.id} to={`/product/${product.id}`} className="product-card">
                        <h5>{product.name}</h5>
                        <p className="price">${product.price}</p>
                        <span className={`stock ${product.inStock ? 'in-stock' : 'out-of-stock'}`}>
                          {product.inStock ? '✓ In Stock' : '✗ Out of Stock'}
                        </span>
                      </Link>
                    ))}
                  </div>
                </div>
              )}

              <div className="info-box">
                <h4>ℹ️ About This Demo</h4>
                <p>
                  This application demonstrates cache behavior through multiple layers:
                </p>
                <ul>
                  <li><strong>Cacheable pages:</strong> Home, Categories, Product Details</li>
                  <li><strong>Non-cacheable pages:</strong> Cart, Account</li>
                  <li><strong>Cache headers:</strong> X-Cache shows HIT/MISS/PASS status</li>
                  <li><strong>Admin actions:</strong> Trigger cache purges</li>
                </ul>
              </div>
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
