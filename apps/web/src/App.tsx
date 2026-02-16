import { BrowserRouter as Router, Routes, Route, Link, useLocation } from 'react-router-dom';
import { useState, useEffect, type MouseEvent } from 'react';
import LandingPage from './pages/LandingPage';
import HomePage from './pages/HomePage';
import CategoryPage from './pages/CategoryPage';
import ProductPage from './pages/ProductPage';
import CartPage from './pages/CartPage';
import AccountPage from './pages/AccountPage';
import AdminPage from './pages/AdminPage';
import { OpenAPI } from './api/core/OpenAPI';

// Get initial dark mode from localStorage (outside component)
const getInitialDarkMode = (): boolean => {
  if (typeof window === 'undefined') return false;
  const saved = localStorage.getItem('darkMode');  
  return saved === 'true';
};

function AppContent() {
  const location = useLocation();
  
  const [darkMode, setDarkMode] = useState(getInitialDarkMode);
  const [apiBaseUrl, setApiBaseUrl] = useState(
    import.meta.env.VITE_API_BASE_URL || 'http://localhost:6081'
  );

  useEffect(() => {
    OpenAPI.BASE = apiBaseUrl;
  }, [apiBaseUrl]);

  useEffect(() => {
    localStorage.setItem('darkMode', String(darkMode));
    document.documentElement.classList.toggle('dark-mode', darkMode);
  }, [darkMode]);

  const handleNavClick = (path: string, e: MouseEvent<HTMLAnchorElement>) => {
    if (location.pathname === path) {
      e.preventDefault();
      // Force reload to refresh cache status
      window.location.reload();
    }
  };

  return (
    <div className="app">
      <header className="header">
        <div className="container">
          <div className="header-content">
            <Link to="/" className="logo" onClick={(e) => handleNavClick('/', e)}>
              <h1>🛒 Edge Cache Lab</h1>
              <span className="tagline">CDN → Varnish → App</span>
            </Link>
            <nav className="nav">
              <Link 
                to="/home" 
                className={location.pathname === '/home' ? 'active' : ''}
                onClick={(e) => handleNavClick('/home', e)}
              >
                Home
              </Link>
              <Link 
                to="/categories" 
                className={location.pathname === '/categories' ? 'active' : ''}
                onClick={(e) => handleNavClick('/categories', e)}
              >
                Categories
              </Link>
              <Link 
                to="/cart" 
                className={location.pathname === '/cart' ? 'active' : ''}
                onClick={(e) => handleNavClick('/cart', e)}
              >
                Cart
              </Link>
              <Link 
                to="/account" 
                className={location.pathname === '/account' ? 'active' : ''}
                onClick={(e) => handleNavClick('/account', e)}
              >
                Account
              </Link>
              <Link 
                to="/admin" 
                className={location.pathname === '/admin' ? 'active' : ''}
                onClick={(e) => handleNavClick('/admin', e)}
              >
                Admin
              </Link>
            </nav>
            <button 
              className="theme-toggle" 
              onClick={() => setDarkMode(!darkMode)}
              aria-label="Toggle dark mode"
              title={darkMode ? 'Switch to light mode' : 'Switch to dark mode'}
            >
              {darkMode ? '☀️' : '🌙'}
            </button>
          </div>
        </div>
      </header>

      <main className="main">
        <Routes>
          <Route path="/" element={<LandingPage />} />
          <Route path="/home" element={<HomePage />} />
          <Route path="/categories" element={<CategoryPage />} />
          <Route path="/product/:id" element={<ProductPage />} />
          <Route path="/cart" element={<CartPage />} />
          <Route path="/account" element={<AccountPage />} />
          <Route path="/admin" element={<AdminPage />} />
        </Routes>
      </main>

      <footer className="footer">
        <div className="container">
          <div className="footer-content">
            <div className="footer-section">
              <h3>Edge Cache Lab</h3>
              <p>Demonstrating production-like CDN caching behavior</p>
            </div>
            <div className="footer-section">
              <h3>Learn More</h3>
              <p>Explore cache headers, HIT/MISS/PASS states, and purge operations</p>
            </div>
            <div className="footer-section">
              <h3>Tech Stack</h3>
              <p>Varnish • Go • React • TypeScript • Kubernetes</p>
            </div>
          </div>
        </div>
      </footer>
      <div className="api-config-panel">
        <div className="container">
          <div className="api-config-card">
            <div className="api-config-copy">
              <h4>API Base URL</h4>
              <p>Optional override for testing different environments or proxy setups.</p>
            </div>
            <div className="api-config-controls">
              <label htmlFor="api-url">API URL</label>
              <input
                id="api-url"
                type="text"
                value={apiBaseUrl}
                onChange={(e) => setApiBaseUrl(e.target.value)}
                placeholder="http://localhost:6081"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function App() {
  return (
    <Router>
      <AppContent />
    </Router>
  );
}

export default App;
