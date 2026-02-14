import { useState } from 'react';
import { OpenAPI } from '../api/core/OpenAPI';

interface PurgeResponse {
  data: unknown;
  headers: Record<string, string>;
}

export default function AdminPage() {
  const [productId, setProductId] = useState('prod-001');
  const [productName, setProductName] = useState('Updated Product');
  const [inStock, setInStock] = useState(true);
  const [purgeToken, setPurgeToken] = useState('test-purge-token');
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [purgeResponse, setPurgeResponse] = useState<PurgeResponse | null>(null);

  const handleUpdate = async () => {
    try {
      setError(null);
      setResult(null);
      setPurgeResponse(null);
      
      const response = await fetch(
        `${OpenAPI.BASE}/admin/product/${productId}`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Purge-Token': purgeToken,
          },
          body: JSON.stringify({
            name: productName,
            inStock: inStock,
          }),
        }
      );

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.message || `HTTP ${response.status}`);
      }

      const data = await response.json();
      
      // Collect interesting headers
      const headers: Record<string, string> = {};
      response.headers.forEach((value, key) => {
        if (key.toLowerCase().includes('purge') || key.toLowerCase().includes('cache')) {
          headers[key] = value;
        }
      });
      
      setPurgeResponse({
        data,
        headers,
      });
      
      setResult('✓ Product updated successfully!');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Update failed');
    }
  };

  const handlePurge = async () => {
    try {
      setError(null);
      setResult(null);
      setPurgeResponse(null);
      
      const response = await fetch(
        `${OpenAPI.BASE}/product/${productId}`,
        {
          method: 'PURGE',
          headers: {
            'X-Purge-Token': purgeToken,
          },
        }
      );

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      setResult('✓ Cache purged successfully!');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Purge failed');
    }
  };

  return (
    <div className="page">
      <div className="container">
        <h2>⚙️ Admin Panel</h2>
        
        <div className="info-banner">
          <strong>🔒 Admin Operations:</strong> Update products and trigger cache purges
        </div>

        <div className="content-section">
          <div className="admin-form">
            <h3>Update Product</h3>
            
            <div className="form-group">
              <label htmlFor="product-id">Product ID:</label>
              <input
                id="product-id"
                type="text"
                value={productId}
                onChange={(e) => setProductId(e.target.value)}
                placeholder="prod-001"
              />
            </div>

            <div className="form-group">
              <label htmlFor="product-name">Product Name:</label>
              <input
                id="product-name"
                type="text"
                value={productName}
                onChange={(e) => setProductName(e.target.value)}
                placeholder="Product Name"
              />
            </div>

            <div className="form-group">
              <label>
                <input
                  type="checkbox"
                  checked={inStock}
                  onChange={(e) => setInStock(e.target.checked)}
                />
                In Stock
              </label>
            </div>

            <div className="form-group">
              <label htmlFor="purge-token">Purge Token:</label>
              <input
                id="purge-token"
                type="text"
                value={purgeToken}
                onChange={(e) => setPurgeToken(e.target.value)}
                placeholder="test-purge-token"
              />
            </div>

            <div className="button-group">
              <button className="btn-primary" onClick={handleUpdate}>
                Update Product
              </button>
              <button className="btn-secondary" onClick={handlePurge}>
                Purge Cache
              </button>
            </div>

            {result && <div className="success-message">{result}</div>}
            {error && <div className="error-message">Error: {error}</div>}
            
            {purgeResponse && (
              <div className="purge-response">
                <h4>Response Details</h4>
                <div className="response-headers">
                  <h5>Purge Headers:</h5>
                  <pre>{JSON.stringify(purgeResponse.headers, null, 2)}</pre>
                </div>
                <div className="response-data">
                  <h5>Response Data:</h5>
                  <pre>{JSON.stringify(purgeResponse.data, null, 2)}</pre>
                </div>
              </div>
            )}
          </div>

          <div className="admin-info">
            <h3>How It Works</h3>
            <ol>
              <li>Update a product with the form above</li>
              <li>The API validates your purge token</li>
              <li>The API returns X-Purge-Tags header</li>
              <li>You can manually purge the cache using PURGE method</li>
              <li>Visit the product page to see the changes and cache behavior</li>
            </ol>
          </div>
        </div>
      </div>
    </div>
  );
}
