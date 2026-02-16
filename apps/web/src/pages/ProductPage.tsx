import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import type { Product } from '../api';
import { OpenAPI } from '../api/core/OpenAPI';
import CacheInfo from '../components/CacheInfo';
import { fetchNoStore } from '../utils/fetchNoStore';
import { headersFromResponse } from '../utils/headersFromResponse';

export default function ProductPage() {
  const { id } = useParams<{ id: string }>();
  const [product, setProduct] = useState<Product | null>(null);
  const [headers, setHeaders] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchData = async () => {
      if (!id) return;
      
      try {
        setLoading(true);
        setError(null);
        
        const response = await fetchNoStore(`${OpenAPI.BASE}/product/${id}`);
        setHeaders(headersFromResponse(response));
        
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        
        const result = await response.json();
        setProduct(result);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to fetch');
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, [id]);

  if (loading) return <div className="loading">Loading...</div>;
  if (error) return <div className="error">Error: {error}</div>;
  if (!product) return <div className="error">Product not found</div>;

  return (
    <div className="page">
      <div className="container">
        <div className="page-layout">
          <div className="page-main">
            <div className="product-detail">
              <h2>{product.name}</h2>
              
              <div className="product-info">
                <div className="product-meta">
                  <p className="product-id">ID: {product.id}</p>
                  <p className="product-price">${product.price}</p>
                  <p className={`product-stock ${product.inStock ? 'in-stock' : 'out-of-stock'}`}>
                    {product.inStock ? '✓ In Stock' : '✗ Out of Stock'}
                  </p>
                </div>
                
                {product.description && (
                  <div className="product-description">
                    <h3>Description</h3>
                    <p>{product.description}</p>
                  </div>
                )}
              </div>
              
              <div className="product-actions">
                <button className="btn-primary" disabled={!product.inStock}>
                  Add to Cart
                </button>
              </div>
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
