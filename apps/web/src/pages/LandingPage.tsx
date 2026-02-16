import { Link } from 'react-router-dom';

export default function LandingPage() {
  return (
    <div className="page">
      <div className="hero-section">
        <div className="container">
          <div className="hero-content">
            <h1 className="hero-title">
              <span className="gradient-text">Edge Cache Lab</span>
            </h1>
            <p className="hero-subtitle">
              Experience Production-Grade CDN Caching in Action
            </p>
            <p className="hero-description">
              Interactive demonstration of multi-layer cache behavior: CDN → Varnish → Application
            </p>
            <div className="hero-actions">
              <Link to="/home" className="btn-hero">
                Explore Products
              </Link>
              <Link to="/admin" className="btn-hero-secondary">
                Try Admin Panel
              </Link>
            </div>
          </div>
        </div>
      </div>

      <div className="container">
        <div className="features-grid">
          <div className="feature-card">
            <div className="feature-icon">⚡</div>
            <h3>Cacheable Pages</h3>
            <p>Home, Categories, and Product pages show HIT/MISS behavior</p>
            <div className="feature-demo">
              <Link to="/product/prod-001" className="feature-link">
                Try Product Page →
              </Link>
            </div>
          </div>

          <div className="feature-card">
            <div className="feature-icon">🚫</div>
            <h3>Non-Cacheable Pages</h3>
            <p>Cart and Account always bypass cache (PASS status)</p>
            <div className="feature-demo">
              <Link to="/cart" className="feature-link">
                View Cart →
              </Link>
            </div>
          </div>

          <div className="feature-card">
            <div className="feature-icon">🔄</div>
            <h3>Cache Purge</h3>
            <p>Admin panel demonstrates cache invalidation workflows</p>
            <div className="feature-demo">
              <Link to="/admin" className="feature-link">
                Admin Panel →
              </Link>
            </div>
          </div>

          <div className="feature-card">
            <div className="feature-icon">📊</div>
            <h3>Real-Time Metrics</h3>
            <p>See X-Cache headers, ETags, and request IDs on every page</p>
            <div className="feature-demo">
              <span className="feature-badge">Live Data</span>
            </div>
          </div>
        </div>

        <div className="info-section">
          <h2 className="section-title">How It Works</h2>
          <div className="info-steps">
            <div className="info-step">
              <div className="step-number">1</div>
              <div className="step-content">
                <h4>First Request</h4>
                <p>Visit a product page - you'll see <strong>X-Cache: MISS</strong> as content is fetched from the origin</p>
              </div>
            </div>
            <div className="info-step">
              <div className="step-number">2</div>
              <div className="step-content">
                <h4>Cache Hit</h4>
                <p>Refresh the page - now you see <strong>X-Cache: HIT</strong> as Varnish serves from cache</p>
              </div>
            </div>
            <div className="info-step">
              <div className="step-number">3</div>
              <div className="step-content">
                <h4>Cache Bypass</h4>
                <p>Visit Cart or Account - these show <strong>X-Cache: PASS</strong> and never cache</p>
              </div>
            </div>
            <div className="info-step">
              <div className="step-number">4</div>
              <div className="step-content">
                <h4>Cache Purge</h4>
                <p>Use Admin panel to update products and purge cache - watch the cache reset</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
