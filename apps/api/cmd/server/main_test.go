package main

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"testing"

	api "edge-cache-lab/apps/api/internal/api"

	"github.com/stretchr/testify/require"
)

// executeRequest, creates a new ResponseRecorder
// then executes the request by calling ServeHTTP in the router
// after which the handler writes the response to the response recorder
// which we can then inspect.
func executeRequest(req *http.Request, s *Server) *httptest.ResponseRecorder {
	rr := httptest.NewRecorder()
	s.Router.ServeHTTP(rr, req)

	return rr
}

// checkResponseCode is a simple utility to check the response code
// of the response
func checkResponseCode(t *testing.T, expected, actual int) {
	if expected != actual {
		t.Errorf("Expected response code %d. Got %d\n", expected, actual)
	}
}

func newServer() *Server {
	s := CreateNewServer()
	s.MountHandlers()
	return s
}

func TestHealth(t *testing.T) {
	t.Setenv("INSTANCE_NAME", "test-instance")
	s := newServer()
	req, _ := http.NewRequest("GET", "/health", nil)
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusOK, response.Code)
	require.Equal(t, "application/json", response.Header().Get("Content-Type"))
	require.NotEmpty(t, response.Header().Get("X-Request-Id"))

	var payload api.Health
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	require.Equal(t, "ok", payload.Status)
	require.Equal(t, "test-instance", payload.Instance)
	require.False(t, payload.Timestamp.IsZero())
	require.NotNil(t, payload.RequestId)
	require.NotEmpty(t, *payload.RequestId)
}

func TestHomepage(t *testing.T) {
	s := newServer()

	req, _ := http.NewRequest("GET", "/", nil)
	req.Header.Set("User-Agent", "contract-test")
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusOK, response.Code)
	requireCacheHeaders(t, response)

	var payload api.Homepage
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), &payload))
	require.Equal(t, "Edge Cache Lab Store", payload.Title)
	require.False(t, payload.Meta.Timestamp.IsZero())
	require.NotEmpty(t, payload.Meta.Instance)
	require.NotEmpty(t, payload.Meta.RequestId)
	require.NotNil(t, payload.Meta.HeadersReceived)
	require.Equal(t, "contract-test", (*payload.Meta.HeadersReceived)["User-Agent"])
}

func TestListCategories(t *testing.T) {
	s := newServer()

	req, _ := http.NewRequest("GET", "/category", nil)
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusOK, response.Code)
	requireCacheHeaders(t, response)

	var payload struct {
		Categories []api.Category   `json:"categories"`
		Meta       api.ResponseMeta `json:"meta"`
	}
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), &payload))
	require.NotEmpty(t, payload.Categories)
	require.False(t, payload.Meta.Timestamp.IsZero())
	require.NotEmpty(t, payload.Meta.Instance)
	require.NotEmpty(t, payload.Meta.RequestId)
}

func TestGetProduct(t *testing.T) {
	s := newServer()

	req, _ := http.NewRequest("GET", "/product/prod-001", nil)
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusOK, response.Code)
	requireCacheHeaders(t, response)

	var payload api.Product
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), &payload))
	require.Equal(t, "prod-001", payload.Id)
	require.Equal(t, "Wireless Headphones", payload.Name)
}

func TestGetProductNotFound(t *testing.T) {
	s := newServer()

	req, _ := http.NewRequest("GET", "/product/unknown", nil)
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusNotFound, response.Code)
	require.NotEmpty(t, response.Header().Get("X-Request-Id"))

	var payload api.Error
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), &payload))
	require.Equal(t, "not_found", payload.Error)
	require.NotEmpty(t, payload.RequestId)
}

func TestCartNoCache(t *testing.T) {
	s := newServer()

	req, _ := http.NewRequest("GET", "/cart", nil)
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusOK, response.Code)
	require.Equal(t, "no-store, no-cache, must-revalidate", response.Header().Get("Cache-Control"))

	var payload api.Cart
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), &payload))
	require.NotEmpty(t, payload.Id)
	require.False(t, payload.Meta.Timestamp.IsZero())
}

func TestAccountNoCache(t *testing.T) {
	s := newServer()

	req, _ := http.NewRequest("GET", "/account", nil)
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusOK, response.Code)
	require.Equal(t, "no-store, no-cache, must-revalidate", response.Header().Get("Cache-Control"))

	var payload api.Account
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), &payload))
	require.Equal(t, "user-001", payload.Id)
	require.False(t, payload.Meta.Timestamp.IsZero())
}

func TestUpdateProduct(t *testing.T) {
	s := newServer()

	body, err := json.Marshal(api.ProductUpdate{
		Name:    stringPtr("Updated Name"),
		InStock: boolPtr(false),
	})
	require.NoError(t, err)

	req, _ := http.NewRequest("POST", "/admin/product/prod-001", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusOK, response.Code)
	require.Equal(t, "product:prod-001", response.Header().Get("X-Purge-Tags"))

	var payload api.Product
	require.NoError(t, json.Unmarshal(response.Body.Bytes(), &payload))
	require.Equal(t, "Updated Name", payload.Name)
	require.False(t, payload.InStock)
}

func TestRequestLogging(t *testing.T) {
	var buffer bytes.Buffer
	original := log.Writer()
	log.SetOutput(&buffer)
	defer log.SetOutput(original)

	s := newServer()
	req, _ := http.NewRequest("GET", "/health", nil)
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusOK, response.Code)

	logOutput := buffer.String()
	require.Contains(t, logOutput, "request_id=")
	require.Contains(t, logOutput, "latency_ms=")
}

func requireCacheHeaders(t *testing.T, response *httptest.ResponseRecorder) {
	t.Helper()
	require.Equal(t, "public, max-age=60", response.Header().Get("Cache-Control"))
	require.Equal(t, "max-age=120", response.Header().Get("Surrogate-Control"))
	require.NotEmpty(t, response.Header().Get("ETag"))
	require.Equal(t, "MISS", response.Header().Get("X-Cache"))
	require.NotEmpty(t, response.Header().Get("X-Request-Id"))
}

func boolPtr(value bool) *bool {
	return &value
}
