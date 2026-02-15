import { useEffect, useState } from 'react';
import type { Cart } from '../api';
import { OpenAPI } from '../api/core/OpenAPI';
import CacheInfo from '../components/CacheInfo';
import { fetchNoStore } from '../utils/fetchNoStore';
import { headersFromResponse } from '../utils/headersFromResponse';

export default function CartPage() {
  const [cart, setCart] = useState<Cart | null>(null);
  const [headers, setHeaders] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);
        setError(null);
        
        const response = await fetchNoStore(`${OpenAPI.BASE}/cart`);
        setHeaders(headersFromResponse(response));
        
        const result = await response.json();
        setCart(result);
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
  if (!cart) return <div className="error">No cart data</div>;

  const total = cart.items?.reduce((sum, item) => sum + (item.price * item.quantity), 0) || 0;

  return (
    <div className="page">
      <div className="container">
        <h2>🛒 Shopping Cart</h2>
        
        <div className="info-banner">
          <strong>⚠️ Non-Cacheable Page:</strong> This page should always show X-Cache: PASS
        </div>

        <CacheInfo meta={cart.meta} headers={headers} />

        <div className="content-section">
          {cart.items && cart.items.length > 0 ? (
            <>
              <div className="cart-items">
                {cart.items.map((item) => (
                  <div key={item.productId} className="cart-item">
                    <div className="cart-item-info">
                      <h4>{item.productId}</h4>
                      <p className="cart-item-quantity">Quantity: {item.quantity}</p>
                    </div>
                    <div className="cart-item-price">
                      ${(item.price * item.quantity).toFixed(2)}
                    </div>
                  </div>
                ))}
              </div>
              
              <div className="cart-summary">
                <h3>Total: ${total.toFixed(2)}</h3>
                <button className="btn-primary">Proceed to Checkout</button>
              </div>
            </>
          ) : (
            <div className="empty-state">Your cart is empty</div>
          )}
        </div>
      </div>
    </div>
  );
}
