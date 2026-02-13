package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

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

func TestHelloWorld(t *testing.T) {
	// Create a New Server Struct
	s := CreateNewServer()
	// Mount Handlers
	s.MountHandlers()

	// Create a New Request
	req, _ := http.NewRequest("GET", "/", nil)

	// Execute Request
	response := executeRequest(req, s)

	// Check the response code
	checkResponseCode(t, http.StatusOK, response.Code)

	// We can use testify/require to assert values, as it is more convenient
	require.Equal(t, "Hello World!", response.Body.String())
}

type healthPayload struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
	Instance  string `json:"instance"`
	RequestID string `json:"request_id"`
}

func TestHealth(t *testing.T) {
	s := CreateNewServer()
	s.MountHandlers()

	os.Setenv("INSTANCE_NAME", "test-instance")
	req, _ := http.NewRequest("GET", "/health", nil)
	response := executeRequest(req, s)

	checkResponseCode(t, http.StatusOK, response.Code)
	require.Equal(t, "application/json", response.Header().Get("Content-Type"))

	var payload healthPayload
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if payload.Status != "ok" {
		t.Fatalf("expected status ok, got %q", payload.Status)
	}

	if payload.RequestID == "" {
		t.Fatalf("expected request_id to be set")
	}

	if payload.Instance != "test-instance" {
		t.Fatalf("expected instance test-instance, got %q", payload.Instance)
	}
}
