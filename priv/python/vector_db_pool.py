"""
VectorDB Connection Pool and Retry Utilities

Provides connection pooling, retry logic with exponential backoff,
health checks, and metrics tracking for vector database operations.
"""

import time
import hashlib
import json
import threading
from typing import Dict, Any, Optional, Callable
from dataclasses import dataclass, field
from datetime import datetime
from collections import deque
import logging

logger = logging.getLogger(__name__)

@dataclass
class RequestMetrics:
    """Track request metrics for a backend."""
    total_requests: int = 0
    successful_requests: int = 0
    failed_requests: int = 0
    total_latency_ms: float = 0.0
    latency_history: deque = field(default_factory=lambda: deque(maxlen=100))
    
    def record_success(self, latency_ms: float):
        self.total_requests += 1
        self.successful_requests += 1
        self.total_latency_ms += latency_ms
        self.latency_history.append({
            "timestamp": datetime.now().isoformat(),
            "latency_ms": latency_ms,
            "success": True
        })
    
    def record_failure(self, latency_ms: float):
        self.total_requests += 1
        self.failed_requests += 1
        self.latency_history.append({
            "timestamp": datetime.now().isoformat(),
            "latency_ms": latency_ms,
            "success": False
        })
    
    def avg_latency_ms(self) -> float:
        if self.total_requests == 0:
            return 0.0
        return self.total_latency_ms / self.total_requests
    
    def success_rate(self) -> float:
        if self.total_requests == 0:
            return 1.0
        return self.successful_requests / self.total_requests
    
    def to_dict(self) -> Dict:
        return {
            "total_requests": self.total_requests,
            "successful_requests": self.successful_requests,
            "failed_requests": self.failed_requests,
            "avg_latency_ms": self.avg_latency_ms(),
            "success_rate": self.success_rate()
        }


class ConnectionPool:
    """
    Connection pool for managing database connections.
    
    Maintains a pool of connections and provides methods for
    acquiring and releasing connections.
    """
    
    def __init__(
        self,
        max_connections: int = 10,
        connection_timeout: float = 30.0,
        max_retries: int = 3,
        retry_base_delay: float = 0.1,
        retry_max_delay: float = 10.0
    ):
        self.max_connections = max_connections
        self.connection_timeout = connection_timeout
        self.max_retries = max_retries
        self.retry_base_delay = retry_base_delay
        self.retry_max_delay = retry_max_delay
        
        self._connections = []
        self._available = threading.Semaphore(max_connections)
        self._lock = threading.Lock()
        self._metrics = RequestMetrics()
        self._healthy = True
        
    def execute_with_retry(
        self,
        operation: Callable,
        *args,
        **kwargs
    ) -> Any:
        """
        Execute an operation with exponential backoff retry.
        
        Args:
            operation: Callable to execute
            *args: Positional arguments for operation
            **kwargs: Keyword arguments for operation
            
        Returns:
            Result of operation
            
        Raises:
            Exception: After max_retries exceeded
        """
        last_exception = None
        
        for attempt in range(self.max_retries + 1):
            start_time = time.time()
            
            try:
                # Try to acquire connection
                if not self._available.acquire(timeout=self.connection_timeout):
                    raise TimeoutError("Connection pool exhausted")
                
                try:
                    result = operation(*args, **kwargs)
                    latency_ms = (time.time() - start_time) * 1000
                    self._metrics.record_success(latency_ms)
                    self._healthy = True
                    return result
                    
                finally:
                    self._available.release()
                    
            except (ConnectionError, TimeoutError, OSError) as e:
                last_exception = e
                latency_ms = (time.time() - start_time) * 1000
                self._metrics.record_failure(latency_ms)
                
                if attempt < self.max_retries:
                    delay = min(
                        self.retry_base_delay * (2 ** attempt),
                        self.retry_max_delay
                    )
                    logger.warning(
                        f"Operation failed (attempt {attempt + 1}/{self.max_retries + 1}): {e}. "
                        f"Retrying in {delay:.2f}s..."
                    )
                    time.sleep(delay)
                else:
                    self._healthy = False
                    raise
            
            except Exception as e:
                latency_ms = (time.time() - start_time) * 1000
                self._metrics.record_failure(latency_ms)
                raise
        
        raise last_exception
    
    def health_check(self) -> Dict[str, Any]:
        """
        Perform a health check on the connection pool.
        
        Returns:
            Dict with health status
        """
        return {
            "healthy": self._healthy,
            "metrics": self._metrics.to_dict(),
            "available_connections": self._available._value,
            "max_connections": self.max_connections
        }
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get request metrics."""
        return self._metrics.to_dict()
    
    def is_healthy(self) -> bool:
        """Check if the pool is healthy."""
        return self._healthy and self._metrics.success_rate() > 0.9


class QueryCache:
    """
    Simple TTL-based cache for search queries.
    
    Caches search results to reduce redundant database calls.
    """
    
    def __init__(
        self,
        max_size: int = 1000,
        ttl_seconds: float = 300.0
    ):
        self.max_size = max_size
        self.ttl_seconds = ttl_seconds
        self._cache = {}
        self._lock = threading.Lock()
        self._hits = 0
        self._misses = 0
    
    def _make_key(self, query: list, top_k: int, filter: Optional[dict]) -> str:
        """Create a cache key from query parameters."""
        query_hash = hashlib.sha256(
            json.dumps(query, sort_keys=True).encode()
        ).hexdigest()
        
        filter_hash = hashlib.sha256(
            json.dumps(filter or {}, sort_keys=True).encode()
        ).hexdigest() if filter else "nofilter"
        
        return f"{query_hash}_{filter_hash}_{top_k}"
    
    def get(self, query: list, top_k: int, filter: Optional[dict]) -> Optional[list]:
        """
        Get cached results for a query.
        
        Returns:
            Cached results or None if not found/expired
        """
        key = self._make_key(query, top_k, filter)
        
        with self._lock:
            if key not in self._cache:
                self._misses += 1
                return None
            
            cached = self._cache[key]
            if time.time() - cached["timestamp"] > self.ttl_seconds:
                del self._cache[key]
                self._misses += 1
                return None
            
            self._hits += 1
            return cached["results"]
    
    def set(self, query: list, top_k: int, filter: Optional[dict], results: list):
        """Cache search results."""
        key = self._make_key(query, top_k, filter)
        
        with self._lock:
            # Evict oldest if at capacity
            if len(self._cache) >= self.max_size:
                oldest_key = min(
                    self._cache.keys(),
                    key=lambda k: self._cache[k]["timestamp"]
                )
                del self._cache[oldest_key]
            
            self._cache[key] = {
                "results": results,
                "timestamp": time.time()
            }
    
    def clear(self):
        """Clear the cache."""
        with self._lock:
            self._cache.clear()
    
    def stats(self) -> Dict[str, Any]:
        """Get cache statistics."""
        total = self._hits + self._misses
        hit_rate = self._hits / total if total > 0 else 0.0
        
        return {
            "size": len(self._cache),
            "max_size": self.max_size,
            "hits": self._hits,
            "misses": self._misses,
            "hit_rate": hit_rate
        }
    
    def invalidate(self, query: list, top_k: int, filter: Optional[dict] = None):
        """Invalidate cached results for a specific query."""
        key = self._make_key(query, top_k, filter)
        
        with self._lock:
            self._cache.pop(key, None)


class CircuitBreaker:
    """
    Circuit breaker for preventing cascade failures.
    
    States:
    - CLOSED: Normal operation
    - OPEN: Failing, reject requests
    - HALF_OPEN: Testing if service recovered
    """
    
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"
    
    def __init__(
        self,
        failure_threshold: int = 5,
        success_threshold: int = 3,
        timeout_seconds: float = 30.0
    ):
        self.failure_threshold = failure_threshold
        self.success_threshold = success_threshold
        self.timeout_seconds = timeout_seconds
        
        self._state = self.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._last_failure_time = None
        self._lock = threading.Lock()
    
    def __enter__(self):
        """Context manager entry."""
        if not self.can_execute():
            raise CircuitBreakerOpen(
                f"Circuit breaker is open. Retry after {self._retry_after():.1f}s"
            )
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        if exc_type is None:
            self.record_success()
        else:
            self.record_failure()
        return False
    
    def can_execute(self) -> bool:
        """Check if execution is allowed."""
        with self._lock:
            if self._state == self.CLOSED:
                return True
            
            if self._state == self.OPEN:
                if time.time() - self._last_failure_time >= self.timeout_seconds:
                    self._state = self.HALF_OPEN
                    self._success_count = 0
                    return True
                return False
            
            # HALF_OPEN
            return True
    
    def record_success(self):
        """Record a successful execution."""
        with self._lock:
            if self._state == self.HALF_OPEN:
                self._success_count += 1
                if self._success_count >= self.success_threshold:
                    self._state = self.CLOSED
                    self._failure_count = 0
            elif self._state == self.CLOSED:
                self._failure_count = 0
    
    def record_failure(self):
        """Record a failed execution."""
        with self._lock:
            self._failure_count += 1
            self._last_failure_time = time.time()
            
            if self._state == self.HALF_OPEN:
                self._state = self.OPEN
            elif self._state == self.CLOSED and self._failure_count >= self.failure_threshold:
                self._state = self.OPEN
    
    def state(self) -> str:
        """Get current state."""
        with self._lock:
            return self._state
    
    def _retry_after(self) -> float:
        """Get seconds until retry is allowed."""
        if self._last_failure_time is None:
            return 0.0
        remaining = self.timeout_seconds - (time.time() - self._last_failure_time)
        return max(0.0, remaining)
    
    def stats(self) -> Dict[str, Any]:
        """Get circuit breaker stats."""
        with self._lock:
            return {
                "state": self._state,
                "failure_count": self._failure_count,
                "success_count": self._success_count,
                "retry_after_seconds": self._retry_after()
            }


class CircuitBreakerOpen(Exception):
    """Raised when circuit breaker is open."""
    pass


# Singleton connection pools for each backend
_pools: Dict[str, ConnectionPool] = {}
_caches: Dict[str, QueryCache] = {}
_breakers: Dict[str, CircuitBreaker] = {}

def get_pool(backend: str) -> ConnectionPool:
    """Get or create connection pool for a backend."""
    if backend not in _pools:
        _pools[backend] = ConnectionPool(
            max_connections=10,
            max_retries=3,
            retry_base_delay=0.1
        )
    return _pools[backend]

def get_cache(backend: str) -> QueryCache:
    """Get or create cache for a backend."""
    if backend not in _caches:
        _caches[backend] = QueryCache(
            max_size=1000,
            ttl_seconds=300.0
        )
    return _caches[backend]

def get_breaker(backend: str) -> CircuitBreaker:
    """Get or create circuit breaker for a backend."""
    if backend not in _breakers:
        _breakers[backend] = CircuitBreaker(
            failure_threshold=5,
            success_threshold=3,
            timeout_seconds=30.0
        )
    return _breakers[backend]

def health_check_all() -> Dict[str, Any]:
    """Check health of all backends."""
    results = {}
    for backend in _pools:
        pool = _pools[backend]
        breaker = _breakers[backend]
        cache = _caches.get(backend)
        
        results[backend] = {
            "pool": pool.health_check(),
            "circuit_breaker": breaker.stats(),
            "cache": cache.stats() if cache else None
        }
    
    return results
