package audit

import (
	"context"
	"fmt"
	"log/slog"
)

// Service is the interface the rest of the codebase calls to write audit events.
// The async implementation enqueues events and writes them off the request path.
type Service interface {
	// WriteAsync enqueues an audit event. Never returns an error to the caller —
	// audit failures are logged but must not break the request.
	WriteAsync(ctx context.Context, e Event)
}

// AsyncService is the production implementation. It runs a background worker
// that drains a buffered channel and writes to the repository.
type AsyncService struct {
	repo  Repository
	queue chan Event
}

const queueSize = 1024

// NewAsyncService constructs the audit service and starts the background writer.
// Call Stop() on shutdown to drain the queue.
func NewAsyncService(repo Repository) *AsyncService {
	s := &AsyncService{
		repo:  repo,
		queue: make(chan Event, queueSize),
	}
	go s.drain()
	return s
}

// WriteAsync enqueues an event. If the queue is full, the event is dropped and
// logged — this is acceptable; availability beats perfect audit completeness.
func (s *AsyncService) WriteAsync(ctx context.Context, e Event) {
	select {
	case s.queue <- e:
	default:
		slog.Warn("audit queue full — event dropped", "event", e.Event)
	}
}

// Stop drains remaining events and shuts down the worker. Call on server shutdown.
func (s *AsyncService) Stop() {
	close(s.queue)
}

func (s *AsyncService) drain() {
	for e := range s.queue {
		// Use a background context — the original request context may be cancelled.
		if err := s.repo.Insert(context.Background(), e); err != nil {
			slog.Error("audit write failed", "event", e.Event, "err", fmt.Sprintf("%v", err))
		}
	}
}
