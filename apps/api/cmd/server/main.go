package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type healthResponse struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
	Instance  string `json:"instance"`
	RequestID string `json:"request_id"`
}

func main() {
	s := CreateNewServer()
	s.MountHandlers()
	err := http.ListenAndServe(":3000", s.Router)
	if err != nil {
		log.Fatalf("level=fatal msg=server_failed err=%v", err)
	}
}

func getInstanceName() string {
	if instance := os.Getenv("INSTANCE_NAME"); instance != "" {
		return instance
	}

	hostname, err := os.Hostname()
	if err != nil {
		return "unknown"
	}

	return hostname
}

// HelloWorld api Handler
func HelloWorldHandler(w http.ResponseWriter, r *http.Request) {
	_, err := w.Write([]byte("Hello World!"))
	if err != nil {
		log.Printf("level=error msg=write_failed err=%v", err)
	}
}

func HealthHandler(w http.ResponseWriter, r *http.Request) {
	instance := getInstanceName()
	requestID := middleware.GetReqID(r.Context())

	resp := healthResponse{
		Status:    "ok",
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		Instance:  instance,
		RequestID: requestID,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Printf("level=error msg=encode_failed err=%v request_id=%s", err, requestID)
	}
}

type Server struct {
	Router chi.Router
}

func CreateNewServer() *Server {
	s := &Server{}
	s.Router = chi.NewRouter()
	return s
}

func (s *Server) MountHandlers() {
	// Mount all Middleware here
	s.Router.Use(middleware.Logger)
	s.Router.Use(middleware.RequestID)
	s.Router.Use(middleware.RealIP)
	s.Router.Use(middleware.Recoverer)

	// Mount all handlers here
	s.Router.Get("/", HelloWorldHandler)
	s.Router.Get("/health", HealthHandler)
}
