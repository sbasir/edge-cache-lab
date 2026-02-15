import { useEffect, useState } from 'react';
import type { Account } from '../api';
import { OpenAPI } from '../api/core/OpenAPI';
import CacheInfo from '../components/CacheInfo';
import { fetchNoStore } from '../utils/fetchNoStore';
import { headersFromResponse } from '../utils/headersFromResponse';

export default function AccountPage() {
  const [account, setAccount] = useState<Account | null>(null);
  const [headers, setHeaders] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);
        setError(null);
        
        const response = await fetchNoStore(`${OpenAPI.BASE}/account`);
        setHeaders(headersFromResponse(response));
        
        const result = await response.json();
        setAccount(result);
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
  if (!account) return <div className="error">No account data</div>;

  return (
    <div className="page">
      <div className="container">
        <h2>👤 My Account</h2>
        
        <div className="info-banner">
          <strong>⚠️ Non-Cacheable Page:</strong> This page should always show X-Cache: PASS
        </div>

        <CacheInfo meta={account.meta} headers={headers} />

        <div className="content-section">
          <div className="account-info">
            <div className="info-item">
              <span className="label">User ID:</span>
              <span className="value">{account.id}</span>
            </div>
            <div className="info-item">
              <span className="label">Email:</span>
              <span className="value">{account.email}</span>
            </div>
            {account.name && (
              <div className="info-item">
                <span className="label">Name:</span>
                <span className="value">{account.name}</span>
              </div>
            )}
          </div>

          <div className="account-actions">
            <button className="btn-secondary">Edit Profile</button>
            <button className="btn-secondary">Change Password</button>
          </div>
        </div>
      </div>
    </div>
  );
}
