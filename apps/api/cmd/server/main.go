package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	api "edge-cache-lab/apps/api/internal/api"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

const (
	cacheControlPublic  = "public, max-age=60"
	surrogateControl    = "max-age=120"
	cacheControlPrivate = "no-store, no-cache, must-revalidate"
	xCacheMiss          = "MISS"
)

type Server struct {
	Router chi.Router
	api    *API
}

type API struct {
	instanceName string
	now          func() time.Time
}

func main() {
	s := CreateNewServer()
	s.MountHandlers()

	addr := ":" + getEnv("PORT", "3000")
	if err := http.ListenAndServe(addr, s.Router); err != nil {
		log.Fatalf("level=fatal msg=server_failed err=%v", err)
	}
}

func CreateNewServer() *Server {
	return &Server{
		Router: chi.NewRouter(),
		api:    NewAPI(),
	}
}

func NewAPI() *API {
	return &API{
		instanceName: getInstanceName(),
		now:          time.Now,
	}
}

func (s *Server) MountHandlers() {
	s.Router.Use(middleware.RequestID)
	s.Router.Use(middleware.RealIP)
	s.Router.Use(middleware.Recoverer)
	s.Router.Use(requestLogger)

	api.HandlerWithOptions(s.api, api.ChiServerOptions{
		BaseRouter:       s.Router,
		ErrorHandlerFunc: s.api.handleError,
	})
}

func getEnv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	return value
}

func getInstanceName() string {
	if instance := getEnv("INSTANCE_NAME", ""); instance != "" {
		return instance
	}

	hostname, err := os.Hostname()
	if err != nil {
		return "unknown"
	}

	return hostname
}

func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		wrapped := middleware.NewWrapResponseWriter(w, r.ProtoMajor)

		next.ServeHTTP(wrapped, r)

		requestID := middleware.GetReqID(r.Context())
		latency := time.Since(start)
		log.Printf(
			"level=info msg=request_complete method=%s path=%s status=%d latency_ms=%d request_id=%s",
			r.Method,
			r.URL.Path,
			wrapped.Status(),
			latency.Milliseconds(),
			requestID,
		)
	})
}

func (a *API) GetHealth(w http.ResponseWriter, r *http.Request) {
	requestID := middleware.GetReqID(r.Context())
	resp := api.Health{
		Status:    "ok",
		Timestamp: a.now().UTC(),
		Instance:  a.instanceName,
	}
	if requestID != "" {
		resp.RequestId = &requestID
	}

	a.writeJSON(w, r, http.StatusOK, resp)
}

func (a *API) GetHomepage(w http.ResponseWriter, r *http.Request) {
	meta := a.responseMeta(r)
	featured := []api.Product{sampleProduct("prod-001"), sampleProduct("prod-002")}
	resp := api.Homepage{
		Title:    "Edge Cache Lab Store",
		Featured: featured,
		Meta:     meta,
	}

	a.setCacheHeaders(w, "W/\"homepage\"")
	a.writeJSON(w, r, http.StatusOK, resp)
}

func (a *API) ListCategories(w http.ResponseWriter, r *http.Request) {
	meta := a.responseMeta(r)
	count := 2
	categories := []api.Category{
		{
			Id:           "cat-001",
			Name:         "Electronics",
			Slug:         "electronics",
			Description:  stringPtr("All electronic products"),
			ProductCount: &count,
		},
		{
			Id:           "cat-002",
			Name:         "Home",
			Slug:         "home",
			Description:  stringPtr("Home and kitchen"),
			ProductCount: &count,
		},
	}

	resp := struct {
		Categories []api.Category   `json:"categories"`
		Meta       api.ResponseMeta `json:"meta"`
	}{
		Categories: categories,
		Meta:       meta,
	}

	a.setCacheHeaders(w, "W/\"category\"")
	a.writeJSON(w, r, http.StatusOK, resp)
}

func (a *API) GetProduct(w http.ResponseWriter, r *http.Request, id string) {
	product, ok := findProduct(id)
	if !ok {
		a.writeError(w, r, http.StatusNotFound, "not_found", "Product not found")
		return
	}

	a.setCacheHeaders(w, fmt.Sprintf("W/\"product-%s\"", id))
	a.writeJSON(w, r, http.StatusOK, product)
}

func (a *API) GetCart(w http.ResponseWriter, r *http.Request) {
	meta := a.responseMeta(r)
	product := sampleProduct("prod-001")
	item := api.CartItem{
		ProductId:   product.Id,
		ProductName: &product.Name,
		Quantity:    1,
		Price:       product.Price,
	}
	resp := api.Cart{
		Id:       "cart-001",
		Items:    []api.CartItem{item},
		Total:    product.Price,
		Currency: stringPtr("USD"),
		Meta:     meta,
	}

	w.Header().Set("Cache-Control", cacheControlPrivate)
	a.writeJSON(w, r, http.StatusOK, resp)
}

func (a *API) GetAccount(w http.ResponseWriter, r *http.Request) {
	meta := a.responseMeta(r)
	createdAt := a.now().UTC().Add(-24 * time.Hour)
	resp := api.Account{
		Id:        "user-001",
		Email:     "user@example.com",
		Name:      stringPtr("Jane Doe"),
		CreatedAt: &createdAt,
		Meta:      meta,
	}

	w.Header().Set("Cache-Control", cacheControlPrivate)
	a.writeJSON(w, r, http.StatusOK, resp)
}

func (a *API) UpdateProduct(w http.ResponseWriter, r *http.Request, id string) {
	var update api.ProductUpdate
	if err := json.NewDecoder(r.Body).Decode(&update); err != nil {
		a.writeError(w, r, http.StatusBadRequest, "invalid_request", "Invalid JSON body")
		return
	}

	product, ok := findProduct(id)
	if !ok {
		a.writeError(w, r, http.StatusNotFound, "not_found", "Product not found")
		return
	}

	if update.Name != nil {
		product.Name = *update.Name
	}
	if update.Description != nil {
		product.Description = update.Description
	}
	if update.Price != nil {
		product.Price = *update.Price
	}
	if update.InStock != nil {
		product.InStock = *update.InStock
	}

	w.Header().Set("X-Purge-Tags", fmt.Sprintf("product:%s", id))
	a.writeJSON(w, r, http.StatusOK, product)
}

func (a *API) handleError(w http.ResponseWriter, r *http.Request, err error) {
	a.writeError(w, r, http.StatusBadRequest, "bad_request", err.Error())
}

func (a *API) setCacheHeaders(w http.ResponseWriter, etag string) {
	w.Header().Set("Cache-Control", cacheControlPublic)
	w.Header().Set("Surrogate-Control", surrogateControl)
	w.Header().Set("ETag", etag)
	w.Header().Set("X-Cache", xCacheMiss)
}

func (a *API) writeJSON(w http.ResponseWriter, r *http.Request, status int, payload interface{}) {
	setRequestIDHeader(w, r)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	if err := json.NewEncoder(w).Encode(payload); err != nil {
		requestID := middleware.GetReqID(r.Context())
		log.Printf("level=error msg=encode_failed err=%v request_id=%s", err, requestID)
	}
}

func (a *API) writeError(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	requestID := middleware.GetReqID(r.Context())
	resp := api.Error{
		Error:     code,
		Message:   message,
		RequestId: requestID,
		Timestamp: timePtr(a.now().UTC()),
	}

	a.writeJSON(w, r, status, resp)
}

func (a *API) responseMeta(r *http.Request) api.ResponseMeta {
	requestID := middleware.GetReqID(r.Context())
	headers := map[string]string{}
	for key, values := range r.Header {
		if len(values) > 0 {
			headers[key] = strings.Join(values, ",")
		}
	}

	return api.ResponseMeta{
		Timestamp:       a.now().UTC(),
		Instance:        a.instanceName,
		RequestId:       requestID,
		HeadersReceived: &headers,
	}
}

func setRequestIDHeader(w http.ResponseWriter, r *http.Request) {
	requestID := middleware.GetReqID(r.Context())
	if requestID != "" {
		w.Header().Set("X-Request-Id", requestID)
	}
}

func stringPtr(value string) *string {
	return &value
}

func timePtr(value time.Time) *time.Time {
	return &value
}

func findProduct(id string) (api.Product, bool) {
	product, ok := productCatalog[id]
	return product, ok
}

var productCatalog = map[string]api.Product{
	"prod-001": sampleProduct("prod-001"),
	"prod-002": sampleProduct("prod-002"),
}

func sampleProduct(id string) api.Product {
	switch id {
	case "prod-002":
		description := "Smart home starter kit"
		categoryID := "cat-002"
		currency := "USD"
		imageURL := "https://example.com/images/prod-002.jpg"
		tags := []string{"home", "smart", "starter"}
		return api.Product{
			Id:          "prod-002",
			Name:        "Smart Home Kit",
			Slug:        "smart-home-kit",
			Description: &description,
			Price:       149.99,
			Currency:    &currency,
			InStock:     true,
			CategoryId:  &categoryID,
			ImageUrl:    &imageURL,
			Tags:        &tags,
		}
	default:
		description := "Wireless headphones with noise cancellation"
		categoryID := "cat-001"
		currency := "USD"
		imageURL := "https://example.com/images/prod-001.jpg"
		tags := []string{"electronics", "audio", "wireless"}
		return api.Product{
			Id:          "prod-001",
			Name:        "Wireless Headphones",
			Slug:        "wireless-headphones",
			Description: &description,
			Price:       199.99,
			Currency:    &currency,
			InStock:     true,
			CategoryId:  &categoryID,
			ImageUrl:    &imageURL,
			Tags:        &tags,
		}
	}
}
