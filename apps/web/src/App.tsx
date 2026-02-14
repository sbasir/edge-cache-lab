import { BrowserRouter as Router, Routes, Route, Link } from 'react-router-dom';
import { useState } from 'react';
import HomePage from './pages/HomePage';
import CategoryPage from './pages/CategoryPage';
import ProductPage from './pages/ProductPage';
import CartPage from './pages/CartPage';
import AccountPage from './pages/AccountPage';
import AdminPage from './pages/AdminPage';
import { OpenAPI } from './api/core/OpenAPI';

function App() {
  const [apiBaseUrl, setApiBaseUrl] = useState(
    import.meta.env.VITE_API_BASE_URL || 'http://localhost:6081'
  );

  // Configure OpenAPI client
  OpenAPI.BASE = apiBaseUrl;

  return (
    <Router>
      <div className="app">
        <header className="header">
          <div className="container">
            <div className="header-content">
              <Link to="/" className="logo">
                <h1>🛒 Edge Cache Lab</h1>
              </Link>
              <nav className="nav">
                <Link to="/">Home</Link>
                <Link to="/categories">Categories</Link>
                <Link to="/cart">Cart</Link>
                <Link to="/account">Account</Link>
                <Link to="/admin">Admin</Link>
              </nav>
            </div>
            <div className="api-config">
              <label htmlFor="api-url">API URL:</label>
              <input
                id="api-url"
                type="text"
                value={apiBaseUrl}
                onChange={(e) => {
                  setApiBaseUrl(e.target.value);
                  OpenAPI.BASE = e.target.value;
                }}
                placeholder="http://localhost:6081"
              />
            </div>
          </div>
        </header>

        <main className="main">
          <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="/categories" element={<CategoryPage />} />
            <Route path="/product/:id" element={<ProductPage />} />
            <Route path="/cart" element={<CartPage />} />
            <Route path="/account" element={<AccountPage />} />
            <Route path="/admin" element={<AdminPage />} />
          </Routes>
        </main>

        <footer className="footer">
          <div className="container">
            <p>
              Edge Cache Lab - Demonstrating CDN → Varnish → App cache behavior
            </p>
          </div>
        </footer>
      </div>
    </Router>
  );
}

export default App;
